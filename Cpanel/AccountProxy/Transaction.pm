package Cpanel::AccountProxy::Transaction;

# cpanel - Cpanel/AccountProxy/Transaction.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::AccountProxy::Transaction

=head1 SYNOPSIS

    Cpanel::AccountProxy::Transaction::set_backends_and_update_services(
        username => 'bobby',
        backend => 'general.example.com',
        worker => {
            Mail => 'mail.example.com',
        },
    );

    Cpanel::AccountProxy::Transaction::unset_all_backends_and_update_services('bobby');

=head1 DESCRIPTION

Because account proxy configuration is stored in multiple places,
it’s important to update those all together as well as to propagate
configuration changes to relevant services. This module implements that.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::AccountProxy::Storage      ();
use Cpanel::CommandQueue               ();
use Cpanel::Config::CpUserGuard        ();
use Cpanel::Config::LoadCpUserFile     ();
use Cpanel::Config::userdata::Guard    ();
use Cpanel::Config::userdata::Load     ();
use Cpanel::Config::WebVhosts          ();
use Cpanel::Exception                  ();
use Cpanel::LinkedNode::LocalAccount   ();
use Cpanel::LinkedNode::Worker::GetAll ();
use Cpanel::LinkedNode::Worker::WHM    ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 set_backends_and_update_services(%opts)

Sets one user’s account proxy backends, including all caches, and updates
relevant services.

Inputs are:

=over

=item * C<username>

=item * C<backend> - (optional) The general proxy backend to assign.
If not given, the existing configuration will be left in place.

=item * C<worker> - (optional) A hashref of worker backends to assign.
Each key is a worker type (e.g., C<Mail>); its value is the backend hostname.
Any worker type not given will have its proxy configuration left in place.

=back

Returns nothing. Any failures trigger an exception. Service updates are
not considered to be failures but will trigger warnings.

=cut

sub set_backends_and_update_services (%opts) {
    my @missing = grep { !$opts{$_} } qw( username );
    die "missing: @missing" if @missing;

    _validate_proxy_backends(
        grep { length } (
            $opts{'backend'},
            $opts{'worker'} ? values( %{ $opts{'worker'} } ) : (),
        ),
    );

    my $username = $opts{'username'};

    my $wvh = Cpanel::Config::WebVhosts->load($username);

    my $cpguard = Cpanel::Config::CpUserGuard->new($username);

    my $cpuser_hr = $cpguard->{'data'};
    _update_cpuser_hr_if_needed( $cpuser_hr, \%opts );

    # NB: We don’t actually have Web worker nodes right now.
    my $web_backend = Cpanel::AccountProxy::Storage::get_worker_backend(
        $cpuser_hr,
        'Web',
    );

    my $queue = Cpanel::CommandQueue->new();

    if ( _account_is_distributed($username) ) {
        _enqueue_service_proxy_propagation(
            $queue, $username,
            @opts{ 'backend', 'worker' },
        );
    }

    my $local_serves_web = _local_account_serves_web($username);

    if ($local_serves_web) {
        _enqueue_for_all_web_vhosts(
            $queue,
            $username,
            $wvh,

            sub ($ud_hr) {
                $ud_hr->{'proxy_backend'} = $web_backend;
            },
        );
    }

    $queue->add( sub { $cpguard->save() } );

    $queue->run();

    if ($local_serves_web) {
        _update_web_for_account_proxy_change($username);
    }

    return;
}

sub _enqueue_service_proxy_propagation ( $queue, $username, $backend = undef, $worker_hr = {} ) {
    my %set_api_args = (
        username => $username,
        general  => $backend,
    );

    for my $svc_group ( keys %$worker_hr ) {
        push $set_api_args{'service_group'}->@*,         $svc_group;
        push $set_api_args{'service_group_backend'}->@*, $worker_hr->{$svc_group};
    }

    my %alias_old_proxies;

    my %alias_todo;
    my %alias_undo;

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username => $username,

        remote_action => sub ($node_obj) {
            my $api   = $node_obj->get_remote_api();
            my $alias = $node_obj->alias();

            my $did_unset;

            $alias_todo{$alias} = sub {
                my $resp = $api->request_whmapi1_or_die(
                    'get_service_proxy_backends',
                    { username => $username },
                );

                $alias_old_proxies{$alias} = $resp->get_data();

                if ($backend) {
                    $api->request_whmapi1_or_die(
                        'set_service_proxy_backends',
                        \%set_api_args,
                    );
                }
                else {
                    $api->request_whmapi1_or_die(
                        'unset_all_service_proxy_backends',
                        { username => $username },
                    );
                    $did_unset = 1;
                }
            };

            $alias_undo{$alias} = sub {
                my $old_ar = $alias_old_proxies{$alias};

                my ( $general, @svc_groups, @backends );

                for my $item_hr (@$old_ar) {
                    my $backend = $item_hr->{'backend'};

                    next if !$backend;

                    if ( my $sg = $item_hr->{'service_group'} ) {
                        push @svc_groups, $sg;
                        push @backends,   $backend;
                    }
                    else {
                        $general = $backend;
                    }
                }

                # We have to unset then set in order to get back
                # to the proxying configuration we had previously.
                if ( !$did_unset ) {
                    $api->request_whmapi1_or_die(
                        'unset_all_service_proxy_backends',
                        { username => $username },
                    );
                }

                # General proxy is required before there’s any
                # service-group-specific proxy.
                if ($general) {
                    $api->request_whmapi1_or_die(
                        'set_service_proxy_backends',
                        {
                            username              => $username,
                            general               => $general,
                            service_group         => \@svc_groups,
                            service_group_backend => \@backends,
                        },
                    );
                }
            };
        },
    );

    for my $alias ( sort keys %alias_todo ) {
        $queue->add(
            $alias_todo{$alias},
            $alias_undo{$alias},
            "roll back proxying setup: $alias",
        );
    }

    return;
}

sub _validate_proxy_backends (@names) {
    require Cpanel::Domain::Local;
    require Cpanel::Validate::Domain;
    require Cpanel::Validate::IP;

    for my $name (@names) {
        if ( !Cpanel::Validate::IP::is_valid_ip($name) ) {

            # It might be nice to update this to allow IDNs and the like.
            # But for now this enforces RFC 1035.
            Cpanel::Validate::Domain::valid_rfc_domainname_or_die($name);
        }

        if ( Cpanel::Domain::Local::domain_or_ip_is_on_local_server($name) ) {
            die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” resolves to the local server. Provide a remote hostname or [asis,IP] address instead.', [$name] );
        }
    }

    return;
}

#----------------------------------------------------------------------

=head2 unset_all_backends_and_update_services($username)

Unsets all of one user’s account proxy backends, including all caches,
and updates the relevant services.

Currently there is no function that removes I<just> worker backends;
however, it would be easy to create one if a need arose.

Returns nothing. Any failures trigger an exception.

=cut

sub unset_all_backends_and_update_services ($username) {
    unset_all_backends($username);

    if ( _local_account_serves_web($username) ) {
        _update_web_for_account_proxy_change($username);
    }

    return;
}

=head2 unset_all_backends($username)

Like C<unset_all_backends_and_update_services()> but does B<not>
update services. This is suitable for cases where those services
will be updated anyway, e.g., during an account restoration.

=cut

*_get_worker_types = *Cpanel::LinkedNode::Worker::GetAll::RECOGNIZED_WORKER_TYPES;

sub unset_all_backends ($username) {
    my $wvh = Cpanel::Config::WebVhosts->load($username);

    my $cpguard = Cpanel::Config::CpUserGuard->new($username);

    my $cpuser_hr = $cpguard->{'data'};

    for my $worker_type ( _get_worker_types() ) {
        Cpanel::AccountProxy::Storage::unset_worker_backend(
            $cpuser_hr,
            $worker_type,
        );
    }

    Cpanel::AccountProxy::Storage::unset_backend($cpuser_hr);

    my $queue = Cpanel::CommandQueue->new();

    if ( _account_is_distributed($username) ) {
        _enqueue_service_proxy_propagation(
            $queue, $username,
        );
    }

    if ( _local_account_serves_web($username) ) {
        _enqueue_for_all_web_vhosts(
            $queue,
            $username,
            $wvh,

            sub ($ud_hr) {
                delete $ud_hr->{'proxy_backend'};
            },
        );
    }

    $queue->add( sub { $cpguard->save() } );

    $queue->run();

    return;
}

sub _account_is_distributed ($username) {
    my $cpuser = Cpanel::Config::LoadCpUserFile::load($username);

    return !!Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser);
}

sub _local_account_serves_web ($username) {
    return Cpanel::LinkedNode::LocalAccount::local_account_does( $username, 'Web' );
}

sub _enqueue_for_all_web_vhosts ( $queue, $username, $wvh, $todo_cr ) {
    my @vhost_names = (
        $wvh->main_domain(),
        $wvh->subdomains(),
    );

    my %former_backend;

    # We don’t need to lock the userdata/$username/main file here
    # because we already have a lock on the cpuser file.

    for my $vhost_name (@vhost_names) {
        my @guard_methods = ('new');

        if ( Cpanel::Config::userdata::Load::user_has_ssl_domain( $username, $vhost_name ) ) {
            push @guard_methods, 'new_ssl';
        }

        for my $method (@guard_methods) {
            $queue->add(
                sub {
                    my $udguard = Cpanel::Config::userdata::Guard->$method(
                        $username,
                        $vhost_name,
                    );

                    $former_backend{$vhost_name} = $udguard->data()->{'proxy_backend'};

                    $todo_cr->( $udguard->data() );

                    $udguard->save();
                },
                sub {
                    my $udguard = Cpanel::Config::userdata::Guard->$method(
                        $username,
                        $vhost_name,
                    );

                    $udguard->data()->{'proxy_backend'} = $former_backend{$vhost_name};

                    $udguard->save();
                },
                "$vhost_name web proxy backend",
            );
        }
    }

    return;
}

sub _update_cpuser_hr_if_needed ( $cpuser_hr, $opts_hr ) {
    if ( my $general = $opts_hr->{'backend'} ) {
        Cpanel::AccountProxy::Storage::set_backend( $cpuser_hr, $general );
    }

    if ( my $worker_hr = $opts_hr->{'worker'} ) {
        for my $worker_type ( keys %$worker_hr ) {
            Cpanel::AccountProxy::Storage::set_worker_backend(
                $cpuser_hr,
                $worker_type,
                $worker_hr->{$worker_type},
            );
        }
    }

    return;
}

sub _update_web_for_account_proxy_change ($username) {

    # As of now, only httpd needs to be restarted.
    require Cpanel::HttpUtils::ApRestart::BgSafe;
    require Cpanel::ConfigFiles::Apache::vhost;

    my ( $ok, $why ) = Cpanel::ConfigFiles::Apache::vhost::update_users_vhosts($username);
    if ($ok) {
        Cpanel::HttpUtils::ApRestart::BgSafe::restart();
    }
    else {
        warn locale()->maketext( 'The system failed to rebuild “[_1]”’s web virtual hosts because an error happened: [_2]', $username, $why ) . "\n";
    }

    return;
}

1;
