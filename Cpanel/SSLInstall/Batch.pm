package Cpanel::SSLInstall::Batch;

# cpanel - Cpanel/SSLInstall/Batch.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSLInstall::Batch

=head1 SYNOPSIS

    my ($results_ar, $updater) = Cpanel::SSLInstall::Batch::install_for_user(
        'johnny',
        [
            [ 'johnny.com', $key, $crt, $cab ],
            [ 'subby.johnny.com', $key2, $crt2, $cab2 ],
        ],
    );

=head1 DESCRIPTION

This module implements batched SSL installations. This is useful during
account restorations, i.e., if a restoration requires hundreds or
even thousands of SSL installations.

=cut

#----------------------------------------------------------------------

use Cpanel::Apache::TLS::Write      ();
use Cpanel::Config::userdata::Load  ();
use Cpanel::Context                 ();
use Cpanel::Finally                 ();
use Cpanel::LinkedNode::Worker::WHM ();
use Cpanel::ServerTasks             ();
use Cpanel::SSL::Auto::DeferRestart ();
use Cpanel::SSL::Verify             ();
use Cpanel::SSLInfo                 ();
use Cpanel::SSLInstall              ();
use Cpanel::SSLStorage::User        ();
use Whostmgr::ACLS                  ();

# Referenced in tests
use constant _BATCH_CHUNK_SIZE => 400;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 ($results_ar, $updater) = install_for_user( $USERNAME, \@BATCH )

Installs multiple SSL certificates for a given user.

Each member of @BATCH is an array reference:

=over

=item * vhost name

B<IMPORTANT:> This B<CANNOT> be just any domain on the vhost.
It B<MUST> be the vhost name.

=item * key, in PEM format

=item * certificate, in PEM format

=item * optional, CA bundle (PEM, concatenated)

=back

This returns two scalars:

=over

=item 0) a reference to an array, each of whose members
is an array that contains the C<status>, C<message>, and C<apache_errors>
(respectively) from the underlying C<Cpanel::SSLInstall::real_installssl()>
call.

=item 1) a L<Cpanel::Finally> instance that, when DESTROYed,
enqueues a task queue item to update $USERNAME’s HTTP vhosts.

=back

Note that, to enqueue the HTTP vhost updates immediately,
you can call this function thus:

    ($results_ar) = install_for_user( $username, \@batch );

=cut

sub _propagate_to_worker ( $node_obj, $username, $batch_ar ) {
    require Cpanel::Parallelizer;

    my $parallelizer = Cpanel::Parallelizer->new();

    my @batch_copy = @$batch_ar;

    while ( my @chunk = splice( @batch_copy, 0, _BATCH_CHUNK_SIZE ) ) {
        $parallelizer->queue(
            sub {
                local $@;

                warn if !eval {
                    Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                        node_obj => $node_obj,
                        function => 'enqueue_deferred_ssl_installations',
                        api_opts => {
                            username   => [ ($username) x @chunk ],
                            vhost_name => [ map { $_->[0] } @chunk ],
                            key        => [ map { $_->[1] } @chunk ],
                            crt        => [ map { $_->[2] } @chunk ],
                            cab        => [ map { $_->[3] } @chunk ],
                        },
                    );

                    1;
                };

                return;
            },
        );
    }

    $parallelizer->run();

    return;
}

sub install_for_user ( $username, $batch_ar ) {
    Cpanel::Context::must_be_list();

    # Elements of @$batch_ar that are indeed for one of $username’s vhosts.
    my @verified_batch;

    for my $item_ar (@$batch_ar) {
        if ( !Cpanel::Config::userdata::Load::user_has_domain( $username, $item_ar->[0] ) ) {
            warn "User “$username” does not own vhost “$item_ar->[0]”; skipping …";
            next;
        }

        push @verified_batch, $item_ar;
    }

    my $apache_tls = Cpanel::Apache::TLS::Write->new();

    my $defer_restart = Cpanel::SSL::Auto::DeferRestart->new(qw(apache dovecot));

    local $Cpanel::SSLInfo::SSL_VERIFY_SINGLETON = Cpanel::SSL::Verify->new();

    my ( $user_sslstorage, $user_sslstorage_lock ) = _get_locked_user_sslstorage($username);
    if ( !$user_sslstorage ) {
        warn $user_sslstorage_lock;
    }

    my $hasroot_yn = Whostmgr::ACLS::hasroot();

    my $finally_update_vhosts;

    # Elements of @$batch_ar that have been installed locally successfully.
    my @batch_items_to_propagate;

    my @results;

    # The workflow here will be:
    #
    # 1) Install locally.
    # 2) Propagate to worker A, in parallel chunks of _BATCH_CHUNK_SIZE.
    # 3) Propagate to worker B, in parallel chunks of _BATCH_CHUNK_SIZE.
    # 4) ...
    #
    # Since we only have 1 worker type for now this is fine, but once we have
    # multiple worker types it’ll be advantageous to do all workers’ chunks
    # in parallel.

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username => $username,

        remote_action => sub ($node_obj) {
            _propagate_to_worker( $node_obj, $username, \@batch_items_to_propagate );
        },

        local_action => sub () {
            for my $item_ar (@verified_batch) {
                $finally_update_vhosts ||= Cpanel::Finally->new(
                    sub {
                        Cpanel::ServerTasks::queue_task( ['ApacheTasks'], "update_or_create_users_vhosts $username" );
                    }
                );

                my ( $vhost_name, $key, $crt, $cab ) = @$item_ar;

                my $installssl_hr = Cpanel::SSLInstall::real_installssl(
                    domain => $vhost_name,
                    key    => $key,
                    crt    => $crt,
                    cab    => $cab,

                    installing_user => $username,

                    disclose_user_data => $hasroot_yn,

                    user_sslstorage => $user_sslstorage,
                    apache_tls      => $apache_tls,

                    skip_propagation => 1,

                    # When skip_vhost_update is set we do not create the
                    # virtual hosts at this point.  Only the userdata
                    # is created.
                    # In Vhosts.pm we will create the actual virtual host
                    # entries in httpd.conf
                    skip_vhost_update => 1,
                );

                if ( $installssl_hr->{'status'} ) {
                    push @batch_items_to_propagate, $item_ar;
                }

                push @results, [ @{$installssl_hr}{qw(status  message  apache_errors)} ];

                # Ensure that we don’t keep the caches for 1,000s of vhosts around.
                Cpanel::Config::userdata::Load::clear_memory_cache_for_user_vhost(
                    $username,
                    $vhost_name,
                );
            }
        },
    );

    return ( \@results, $finally_update_vhosts );
}

#
# This code borrowed from Cpanel::SSLInstall in v66
# as it solves the same problem
#
# This will allow us to load the datastore only once rather
# than a separate lock/unlock for both saves.
#
# Stubbed in tests.
sub _get_locked_user_sslstorage {
    my ($user) = @_;
    my $sslstorage = Cpanel::SSLStorage::User->new( user => $user );

    my ( $lock_ok, $lock_msg ) = $sslstorage->_execute_coderef( sub { return $sslstorage->_load_datastore_rw() } );
    return ( 0, $lock_msg ) if !$lock_ok;

    my $hook_at_end_cr = Cpanel::Finally->new(
        sub {
            #commit our changes to disk and release the SSLStorage lock.
            my ( $sv_ok, $sv_msg ) = $sslstorage->_execute_coderef( sub { return $sslstorage->_save_datastore(); } );
            warn $sv_msg if !$sv_ok;
        }
    );
    return ( $sslstorage, $hook_at_end_cr );
}

1;
