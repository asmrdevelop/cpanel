package Cpanel::LinkedNode::Convert::Common::Mail::ToRemote;

# cpanel - Cpanel/LinkedNode/Convert/Common/Mail/ToRemote.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::Common::Mail::ToRemote

=head1 SYNOPSIS

(Not much interesting to show about this module.)

=head1 DESCRIPTION

This module contains various pieces of logic that are common
for mail conversions to a remote node.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::Config::CpUserGuard                           ();
use Cpanel::Exim::ManualMX                                ();
use Cpanel::LinkedNode                                    ();
use Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer ();
use Cpanel::LinkedNode::Worker::Storage                   ();
use Cpanel::LinkedNode::Convert::Common::Child            ();
use Cpanel::LinkedNode::Convert::Common::Mail::Backend    ();
use Cpanel::LinkedNode::Convert::Common::Mail::DNS        ();
use Cpanel::LocaleString                                  ();
use Cpanel::LinkedNode::AccountCache                      ();
use Cpanel::PromiseUtils                                  ();
use Cpanel::Time::ISO                                     ();
use Cpanel::Validate::IP::v4                              ();
use Cpanel::Validate::IP                                  ();

use constant _WORKLOAD => 'Mail';

#----------------------------------------------------------------------

=head1 STEP AND UNDO FUNCTIONS

For all of these functions:

=over

=item * %INPUT is what the converter function receives as input.

=item * $STATE_OBJ is a
L<Cpanel::LinkedNode::Convert::Common::Mail::StateBase> instance.

=item * Nothing is returned.

=back

=head2 step__verify_child_node( \%INPUT, $STATE_OBJ )

A wrapper around L<Cpanel::LinkedNode>’s C<verify_node_capabilities()>.
Expects %INPUT to contain C<worker_alias>; sets $STATE_OBJ’s
C<target_node_obj> parameter.

=cut

sub step__verify_child_node ( $input_hr, $state_obj ) {
    my $node_obj = Cpanel::LinkedNode::verify_node_capabilities(
        alias        => $input_hr->{'worker_alias'},
        capabilities => [_WORKLOAD],
    );

    $state_obj->set( target_node_obj => $node_obj );

    return;
}

=head2 step__determine_dns_updates( \%INPUT, $STATE_OBJ )

A wrapper around L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s
C<determine_zone_updates()>. Expects %INPUT to contain C<username>; sets
$STATE_OBJ’s C<target_node_obj> parameter.


=cut

sub step__determine_dns_updates ( $input_hr, $state_obj ) {
    my $records_to_update = Cpanel::LinkedNode::Convert::Common::Mail::DNS::determine_zone_updates( $input_hr->{'username'}, $state_obj );

    $state_obj->set( records_to_update => $records_to_update );

    return;
}

=head2 undo__copy_archive_to_target( \%INPUT, $STATE_OBJ )

Undoes C<step__copy_archive_to_target()>. Note that, while that logic
is specific to the conversion type, the undo logic is common.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_archive_deleted> and C<target_node_obj>.

=cut

sub undo__copy_archive_to_target ( $input_hr, $state_obj ) {

    # The account restoration logic should delete the archive.
    if ( !$state_obj->get('target_archive_deleted') ) {
        my $p = Cpanel::LinkedNode::Convert::Common::Child::delete_account_archives_p(
            $state_obj->get('target_node_obj'),
            $input_hr->{'username'},
        );

        Cpanel::PromiseUtils::wait_anyevent($p);
    }

    return;
}

=head2 step__target_restore( \%INPUT, $STATE_OBJ )

Restores the user account on the target node.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_cpmove_path> and C<target_node_obj>. Sets
C<target_archive_deleted>.

=cut

sub step__target_restore ( $input_hr, $state_obj ) {
    Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer::execute_account_local_transfer(
        $state_obj->get('target_node_obj')->alias(),
        $input_hr->{'username'},
        $state_obj->get('target_cpmove_path'),
    );

    # Avoid a redundant cleanup API call on failure.
    $state_obj->set( target_archive_deleted => 1 );

    return;
}

=head2 undo__target_restore( \%INPUT, $STATE_OBJ )

Undoes C<step__target_restore()>.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_listaccts_hr> and C<target_node_obj>.

=cut

sub undo__target_restore ( $input_hr, $state_obj ) {

    # Forgo this step if the account already existed:
    return if $state_obj->get('target_listaccts_hr');

    my $api = $state_obj->get('target_node_obj')->get_async_remote_api();

    my $p = $api->request_whmapi1(
        'removeacct',
        { %{$input_hr}{'username'} },
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

=head2 step__determine_preexistence( \%INPUT, $STATE_OBJ )

Determines whether the account already exists on the child node.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_node_obj>. Sets C<target_listaccts_hr> to be the
user’s C<listaccts> WHM API v1 return.

=cut

sub step__determine_preexistence ( $input_hr, $state_obj ) {
    my $data = Cpanel::PromiseUtils::wait_anyevent(
        _get_target_listaccts_p( $input_hr, $state_obj ),
    )->get();

    $state_obj->set(
        target_listaccts_hr => $data && $data->[0],
    );

    return;
}

=head2 step__update_dns( \%INPUT, $STATE_OBJ )

Pushes the needed updates to DNS as per the conversion.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_node_obj> and C<records_to_update> (the return from
L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s
C<determine_zone_updates()>).

=cut

sub step__update_dns ( $input_hr, $state_obj ) {
    my $data = Cpanel::PromiseUtils::wait_anyevent(
        _get_target_listaccts_p( $input_hr, $state_obj ),
    )->get();

    my $listaccts_hr = $data->[0] or do {

        # This should not happen in production but arose in testing,
        # and we might as well leave the sanity-check in place.
        die 'Remote listaccts did not return user, despite that the user should exist.';
    };

    my $ipv4 = $listaccts_hr->{'ip'};
    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ipv4) ) {
        die "Remote listaccts returned invalid “ip” ($ipv4)";
    }

    $ipv4 = _get_public_ipv4( $state_obj, $ipv4 );

    my $ipv6 = $listaccts_hr->{'ipv6'}[0];
    if ( $ipv6 && !Cpanel::Validate::IP::is_valid_ipv6($ipv6) ) {
        die "Remote listaccts returned invalid “ipv6” (@{$listaccts_hr->{'ipv6'}})";
    }

    _do_zone_updates(
        username    => $input_hr->{'username'},
        mailer_name => $state_obj->get('target_node_obj')->hostname(),
        ipv4        => $ipv4,
        ipv6        => $ipv6,
        records     => $state_obj->get('records_to_update'),
    );

    return;
}

=head2 undo__update_dns( \%INPUT, $STATE_OBJ )

Undoes C<step__update_dns()>.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<records_to_update> (the return from
L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s
C<determine_zone_updates()>).

=cut

sub undo__update_dns ( $, $state_obj ) {
    require Cpanel::DnsUtils::Batch;

    my @name_type_value;

    for my $rec_hr ( @{ $state_obj->get('records_to_update') } ) {
        my $value;

        if ( $rec_hr->{'type'} eq 'MX' ) {
            $value = "@{$rec_hr}{'preference','exchange'}";
        }
        elsif ( $rec_hr->{'type'} eq 'CNAME' ) {
            $value = $rec_hr->{'cname'};
        }
        elsif ( grep { $_ eq $rec_hr->{'type'} } qw( A AAAA ) ) {
            $value = $rec_hr->{'address'};
        }
        else {
            die "Bad record type to restore: $rec_hr->{'type'}";
        }

        my $stripped_name = $rec_hr->{'name'} =~ s<\.\z><>r;

        push @name_type_value, [ $stripped_name, $rec_hr->{'type'}, $value ];
    }

    Cpanel::DnsUtils::Batch::set( \@name_type_value );

    return;
}

=head2 step__set_up_local_manual_mx( \%INPUT, $STATE_OBJ )

Sets the local (i.e., parent) server’s manual MX for the user’s domains
to point to the target node.

Expects %INPUT to contain C<username> and $STATE_OBJ to contain
C<target_node_obj>. Sets C<old_local_manual_mx> on $STATE_OBJ.

=cut

sub step__set_up_local_manual_mx ( $input_hr, $state_obj ) {
    my $domains_ar = Cpanel::LinkedNode::Convert::Common::Mail::Backend::get_mail_domains_for_step($input_hr);

    my $hostname = $state_obj->get('target_node_obj')->hostname();

    my %new_mx = map { $_ => $hostname } @$domains_ar;

    $state_obj->set( old_local_manual_mx => Cpanel::Exim::ManualMX::set_manual_mx_redirects( \%new_mx ) );

    return;
}

=head2 undo__set_up_local_manual_mx ( \%INPUT, $STATE_OBJ )

C<step__set_up_local_manual_mx()>’s undo logic.

$STATE_OBJ is a L<Cpanel::LinkedNode::Convert::FromDistributed::Mail::State>
instance. It must contain C<old_local_manual_mx>.

=cut

sub undo__set_up_local_manual_mx ( $, $state_obj ) {
    my $old_mx_hr = $state_obj->get('old_local_manual_mx');
    my @undo      = grep { !defined $old_mx_hr->{$_} } keys %$old_mx_hr;

    my %set = %$old_mx_hr;
    delete @set{@undo};

    if (@undo) {
        try {
            Cpanel::Exim::ManualMX::unset_manual_mx_redirects( \@undo );
        }
        catch {
            @undo = sort @undo;
            warn "Failed to unset manual MX (@undo): $_";
        };
    }

    if (%set) {
        try {
            Cpanel::Exim::ManualMX::set_manual_mx_redirects( \%set );
        }
        catch {
            my @show = map { $_ => $set{$_} } sort keys %set;
            warn "Failed to restore manual MX (@show): $_";
        };
    }

    return;
}

=head2 step__update_local_cpuser ( \%INPUT, $STATE_OBJ )

Saves the new mail node in the user’s local/parent cpuser datastore.

%INPUT must contain C<username>;
$STATE_OBJ must contain C<target_node_obj> and C<target_user_api_token>.
This sets $STATE_OBJ’s C<former_cpuser_mail_worker_cfg>.

=cut

sub step__update_local_cpuser ( $input_hr, $state_obj ) {
    my $guard = Cpanel::Config::CpUserGuard->new( $input_hr->{'username'} );

    my $old_cfg = Cpanel::LinkedNode::Worker::Storage::read( $guard->{'data'}, _WORKLOAD );

    $guard->set_worker_node(
        _WORKLOAD,
        $state_obj->get('target_node_obj')->alias(),
        $state_obj->get('target_user_api_token'),
    );

    $guard->save();

    $state_obj->set( former_cpuser_mail_worker_cfg => $old_cfg );

    return;
}

=head2 undo__update_local_cpuser ( \%INPUT, $STATE_OBJ )

Undoes C<step__update_local_cpuser()>.

%INPUT must contain C<username>;
$STATE_OBJ must contain C<former_cpuser_mail_worker_cfg>.

=cut

sub undo__update_local_cpuser ( $input_hr, $state_obj ) {
    my $guard = Cpanel::Config::CpUserGuard->new( $input_hr->{'username'} );

    if ( my $old_cfg = $state_obj->get('former_cpuser_mail_worker_cfg') ) {
        $guard->set_worker_node(
            _WORKLOAD,
            @$old_cfg[ 0, 1 ],
        );
    }
    else {
        $guard->unset_worker_node(_WORKLOAD);
    }

    $guard->save();

    return;
}

=head2 step__update_distributed_accounts_cache ( \%INPUT, $STATE_OBJ )

Saves the user’s new mail node in the linked-node account cache.

%INPUT must contain C<username>;
$STATE_OBJ must contain C<target_node_obj>.

=cut

sub step__update_distributed_accounts_cache ( $input_hr, $state_obj ) {
    my $p = Cpanel::LinkedNode::AccountCache->new_p()->then(
        sub ($cache) {
            $cache->set_user_parent_data(
                $input_hr->{'username'},
                _WORKLOAD,
                $state_obj->get('target_node_obj')->alias(),
            );

            return $cache->save_p();
        },
    );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

=head2 step__configure_new_child_account ( \%INPUT, $STATE_OBJ )

Configures the (new?) account on the target node to serve as the
child-node component of a distributed-mail account. Should run right after
account creation.

%INPUT must contain C<username>;
$STATE_OBJ must contain C<target_node_obj>. Sets
C<target_user_api_token> in $STATE_OBJ.

=cut

sub step__configure_new_child_account ( $input_hr, $state_obj ) {
    my $api = $state_obj->get('target_node_obj')->get_async_remote_api();

    my $now        = Cpanel::Time::ISO::unix2iso() =~ tr<0-9a-zA-Z><->cr;
    my $token_name = "MailNodeLinkage-$now";

    my @reqs = (
        $api->request_whmapi1(
            'normalize_user_email_configuration',
            {
                username => $input_hr->{'username'},
            },
        ),

        $api->request_whmapi1(
            'PRIVATE_set_child_workloads',
            {
                username => $input_hr->{'username'},
                workload => _WORKLOAD,
            },
        ),

        $api->request_cpanel_uapi(
            $input_hr->{'username'},
            Tokens => 'create_full_access',
            {
                name => $token_name,
            },
        )->then(
            sub ($resp) {
                my $token = $resp->get_data()->{'token'} or do {

                    # This shouldn’t ever happen in production. It came up in
                    # testing, and we might as well leave the check in place.
                    die 'Malformed API response: Tokens::create_full_access succeeded, but response lacks token.';
                };

                $state_obj->set( target_user_api_token => $token );
            }
        ),
    );

    Cpanel::PromiseUtils::wait_anyevent(@reqs);

    return;
}

#----------------------------------------------------------------------

=head1 GENERAL FUNCTIONS

=head2 promise() = determine_preexistence_p( \%INPUT, $STATE_OBJ )

Determines if the account already exists on the target node via
a call to C<listaccts> on that node. Stores the return for the user
in $STATE_OBJ’s C<target_listaccts_hr> and sends a notification to
the output object.

Expects %INPUT to contain C<username> and C<output_obj>.
Expects $STATE_OBJ to contain C<target_node_obj>.

=cut

sub determine_preexistence_p ( $input_hr, $state_obj ) {
    return _get_target_listaccts_p( $input_hr, $state_obj )->then(
        sub ($data) {
            my $listaccts_hr = $data && $data->[0];

            $state_obj->set( target_listaccts_hr => $listaccts_hr );

            my $msg;

            my $username = $input_hr->{'username'};
            my $alias    = $state_obj->get('target_node_obj')->alias();

            if ($listaccts_hr) {
                $msg = locale()->maketext( 'An account named “[_1]” already exists on “[_2]”.', $username, $alias );
            }
            else {
                $msg = locale()->maketext( 'No account named “[_1]” exists on “[_2]”.', $username, $alias );
            }

            $input_hr->{'output_obj'}->out($msg);
        },
    );
}

#----------------------------------------------------------------------

sub _get_target_listaccts_p ( $input_hr, $state_obj ) {
    return Cpanel::LinkedNode::Convert::Common::Child::get_user_listaccts_p(
        $state_obj->get('target_node_obj'),
        $input_hr->{'username'},
    );
}

sub _get_public_ipv4 ( $state_obj, $ipv4 ) {
    my $api = $state_obj->get('target_node_obj')->get_async_remote_api();

    my $p = $api->request_whmapi1(
        'get_public_ip',
        {
            ip => $ipv4,
        },
    )->then(
        sub ($resp) {
            return $resp->get_data()->{'public_ip'};
        },
    );

    return Cpanel::PromiseUtils::wait_anyevent($p)->get();
}

# Wraps L<Cpanel::LinkedNode::Convert::Common::Mail::DNS>’s function
# of the same name. The C<ipv6_msg> argument is not necessary, though.
#
sub _do_zone_updates (%opts) {

    my $ipv6_msg = Cpanel::LocaleString->new('The [asis,DNS] “[_1]” record for “[_2]” ([_3]) resolves to this server. The system needs to update this record to resolve to “[_4]”, but the user “[_5]” does not control any [asis,IPv6] addresses on that server.');

    return Cpanel::LinkedNode::Convert::Common::Mail::DNS::do_zone_updates( %opts, 'ipv6_msg' => $ipv6_msg );
}

1;
