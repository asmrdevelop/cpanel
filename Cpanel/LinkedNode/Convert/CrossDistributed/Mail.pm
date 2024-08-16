package Cpanel::LinkedNode::Convert::CrossDistributed::Mail;

# cpanel - Cpanel/LinkedNode/Convert/CrossDistributed/Mail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::CrossDistributed::Mail

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This module implements a mail “cross-distribution”,
i.e., changing a distributed-mail account’s mail node.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::LinkedNode::Convert::Common::Child                   ();
use Cpanel::LinkedNode::Convert::Common::FromRemote              ();
use Cpanel::LinkedNode::Convert::Common::Mail::FromRemote        ();
use Cpanel::LinkedNode::Convert::Common::Mail::ToRemote          ();
use Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend ();
use Cpanel::LinkedNode::Convert::CrossDistributed::Mail::State   ();
use Cpanel::LinkedNode::Convert::TaskRunner                      ();
use Cpanel::PromiseUtils                                         ();
use Cpanel::UserLock                                             ();

use constant _WORKLOAD => 'Mail';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 convert( %OPTS )

Does the conversion.

%OPTS are:

=over

=item * C<username> - The account’s username.

=item * C<worker_alias> - The I<target> child node’s alias. (C<worker> is
for consistency w/ interfaces that predate the deployment of the term
“child node”.)

=item * C<output_obj> - A L<Cpanel::Output> instance that will receive
notifications while this conversion is in process.

=back

=cut

sub convert (%opts) {
    state @REQUIRED = qw( username  worker_alias  output_obj );

    my @missing = grep { !length $opts{$_} } @REQUIRED;
    die "need: @missing" if @missing;

    my %input = %opts{@REQUIRED};

    my $user_lock = Cpanel::UserLock::create_shared_or_die( $input{'username'} );

    my $state_obj = Cpanel::LinkedNode::Convert::CrossDistributed::Mail::State->new();

    my $old_node_obj = Cpanel::LinkedNode::Convert::Common::FromRemote::get_source_node_obj( $input{'username'}, _WORKLOAD );

    $state_obj->set( source_node_obj => $old_node_obj );

    my $old_node_alias = $old_node_obj->alias();
    my $new_node_alias = $input{'worker_alias'};

    if ( $old_node_alias eq $new_node_alias ) {
        die "Can’t cross-distribute to the same node ($old_node_alias)!";
    }

    $input{'output_obj'}->out(
        locale()->maketext( 'Current “[_1]” node: [_2]', _WORKLOAD, $old_node_alias ),
    );

    my @main_steps = (

        # Ideally these initial tasks would all happen in parallel,
        # but the verify logic is synchronous.

        {
            label => locale()->maketext( 'Verifying “[_1]”’s capabilities …', $new_node_alias ),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__verify_child_node,
        },
        {
            label => locale()->maketext('Retrieving child node settings …'),
            code  => \&_get_child_node_settings,
        },
        {
            label => locale()->maketext('Determining required [asis,DNS] updates …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__determine_dns_updates,
        },

        # --------------------------------------------------

        {
            label => locale()->maketext( 'Creating account archive on “[_1]” …', $old_node_obj->alias() ),
            code  => \&Cpanel::LinkedNode::Convert::Common::FromRemote::step__pkgacct_on_source,

            # This step is a bit odd: its undo component is the
            # same logic as a later step.
            undo       => \&_delete_source_account_archives,
            undo_label => locale()->maketext( 'Deleting account archives on “[_1]” …', $old_node_obj->alias() ),
        },

        {
            label      => locale()->maketext( 'Transferring “[_1]”’s account archive to “[_2]” …', $old_node_obj->alias(), $new_node_alias ),
            code       => \&_make_new_child_download_archive,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__copy_archive_to_target,
            undo_label => sub {

                #return 'SKIPPED';
                return undef if $state_obj->get('target_archive_deleted');
                return locale()->maketext( 'Deleting account archive on “[_1]” …', $new_node_alias );
            },
        },

        {
            label      => locale()->maketext( 'Restoring “[_1]” on “[_2]” …', $input{'username'}, $new_node_alias ),
            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__target_restore,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__target_restore,
            undo_label => sub {
                if ( !$state_obj->get('target_listaccts_hr') ) {
                    return locale()->maketext( 'Deleting “[_1]” on “[_2]” …', $input{'username'}, $new_node_alias );
                }

                return locale()->maketext( 'Because the [asis,cPanel] account already existed on “[_1]”, the system will not delete that account.', $new_node_alias );
            },
        },

        {
            label => locale()->maketext( 'Configuring “[_1]” on “[_2]” …', $input{'username'}, $new_node_alias ),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__configure_new_child_account,
        },

        # This will cause new IMAP/POP3 and SMTP to go to the new
        # node; however, DNS caching will ensure that servers that
        # are “used” to sending to the source server will continue
        # to do so. Since DNS updates are fairly more error-prone than
        # other kinds of changes we’re going to do here, let’s do them
        # right off the bat.
        #
        {
            label      => locale()->maketext('Updating [asis,DNS] …'),
            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__update_dns,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__update_dns,
            undo_label => locale()->maketext('Undoing [asis,DNS] updates …'),
        },

        # ---- BEGIN POTENTIAL LOST MAIL:
        # If a failure happens below, any mail received after the DNS
        # update that got routed to the target node will be LOST!
        # --------------------------------------------------

        # New IMAP/POP3 will go to the target node
        {
            label      => locale()->maketext( 'Configuring service proxying on “[_1]” …', $old_node_alias ),
            code       => \&Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend::step__set_up_source_service_proxy,
            undo_label => locale()->maketext( 'Reverting “[_1]”’s service proxying changes …', $old_node_alias ),
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::undo__set_up_source_service_proxy,
        },

        # This could happen in parallel with the last step, but in the
        # event of failure we’d need a nice way to roll back whatever
        # has been completed.
        {
            label => locale()->maketext( 'Routing “[_1]”’s incoming mail on “[_2]” to “[_3]” …', $input{'username'}, $old_node_alias, $new_node_alias ),

            # TODO: Refactor from FromDistributed
            code       => \&Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend::step__set_up_source_manual_mx,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::undo__set_up_source_manual_mx,
            undo_label => locale()->maketext( 'Reverting “[_1]”’s mail routing changes …', $old_node_alias ),
        },

        # ---- END POTENTIAL LOST MAIL ----

        {
            label => locale()->maketext( 'Copying mail from “[_1]” to “[_2]” …', $old_node_alias, $new_node_alias ),
            code  => \&Cpanel::LinkedNode::Convert::CrossDistributed::Mail::Backend::step__make_target_node_download_mail,
        },

        {
            label => locale()->maketext( 'Routing “[_1]”’s local incoming mail to “[_2]” …', $input{'username'}, $new_node_alias ),

            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__set_up_local_manual_mx,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__set_up_local_manual_mx,
            undo_label => locale()->maketext('Reverting local mail routing changes …'),
        },

        {
            label      => locale()->maketext( 'Updating “[_1]”’s local configuration …', $input{'username'} ),
            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__update_local_cpuser,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__update_local_cpuser,
            undo_label => locale()->maketext( 'Reverting “[_1]”’s local configuration changes …', $input{'username'} ),
        },

        {
            label => locale()->maketext('Updating local caches …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__update_distributed_accounts_cache,
            tags  => ['final'],
        },

        #------------------------------------------------------------
        # POINT OF NO RETURN! Once we’re here the migration is
        # complete; any further failures are nonfatal.
        #------------------------------------------------------------

        {
            label => locale()->maketext('Finishing up …'),
            code  => \&_cleanup,
        },
    );

    Cpanel::LinkedNode::Convert::TaskRunner->run(
        $opts{'output_obj'},
        \@main_steps,
        \%input,
        $state_obj,
    );

    $opts{'output_obj'}->success( locale()->maketext( '“[_1]” now uses “[_2]” for “[_3]”.', $opts{'username'}, $new_node_alias, _WORKLOAD ) );

    return;
}

sub _cleanup ( $input_hr, $state_obj ) {
    my $source_alias = $state_obj->get('source_node_obj')->alias();

    my @promises = (
        Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::delete_source_account_archives_p( $input_hr, $state_obj )->catch(
            sub ($why) {
                warn "Failed to delete account archives on $source_alias: $why";
            },
        ),

        Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::kick_source_connections_p( $input_hr, $state_obj )->catch(
            sub ($why) {
                warn "Failed to terminate mailbox connections on $source_alias: $why";
            },
        ),

        Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::unchildify_former_child_account_p( $input_hr, $state_obj )->catch(
            sub ($why) {
                warn "Failed to reconfigure account on $source_alias: $why";
            },
        ),
    );

    Cpanel::PromiseUtils::wait_anyevent(@promises);

    return;
}

sub _delete_source_account_archives ( $input_hr, $state_obj ) {
    my $p = Cpanel::LinkedNode::Convert::Common::Mail::FromRemote::delete_source_account_archives_p( $input_hr, $state_obj );

    Cpanel::PromiseUtils::wait_anyevent($p);

    return;
}

sub _get_child_node_settings ( $input_hr, $state_obj ) {

    my $old_node_obj = $state_obj->get('source_node_obj');

    my $network_p = Cpanel::LinkedNode::Convert::Common::Child::get_network_setup_p($old_node_obj)->then(
        sub ($payload_ar) {
            my ( $hostname, $ips_ar ) = @$payload_ar;

            $state_obj->set(
                source_node_hostname => $hostname,
                source_node_ips      => $ips_ar,
            );
        },
    );

    my $new_node_obj = $state_obj->get('target_node_obj');

    my $new_api = $new_node_obj->get_async_remote_api();

    my $filesys_p = $new_api->request_whmapi1('get_homedir_roots')->then(
        sub ($result) {
            my $path = $result->get_data()->[0]{'path'} or do {
                require Data::Dumper;
                warn Data::Dumper::Dumper($result);

                die 'Got no new homedir root!';
            };

            my $alias = $new_node_obj->alias();

            $state_obj->set( target_homedir_root => $path );
        },
    );

    my $determine_p = Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::determine_preexistence_p( $input_hr, $state_obj );

    Cpanel::PromiseUtils::wait_anyevent( $network_p, $filesys_p, $determine_p );

    return;
}

sub _make_new_child_download_archive ( $input_hr, $state_obj ) {

    my $home = $state_obj->get('target_homedir_root');

    my $new_cpmove_path = "$home/cpmove-$input_hr->{'username'}";

    $input_hr->{'output_obj'}->out(
        locale()->maketext('Destination path:') . " $new_cpmove_path",
    );

    $state_obj->set(
        target_cpmove_path => $new_cpmove_path,
    );

    my $cstream = $state_obj->get('target_node_obj')->get_commandstream();

    my $old_node_obj = $state_obj->get('source_node_obj');

    $state_obj->get('source_backup_dir') =~ m<(.+)/(.+)>;
    my ( $remote_dir, $remote_name ) = ( $1, $2 );

    my $tar_p = $cstream->request(
        'tardownload',
        hostname         => $state_obj->get('source_node_hostname'),
        username         => $old_node_obj->username(),
        api_token        => $old_node_obj->api_token(),
        tls_verification => $old_node_obj->allow_bad_tls() ? 'off' : 'on',

        local_directory  => $home,
        remote_directory => $remote_dir,
        paths            => [$remote_name],
    )->then(
        sub ($req) {
            my $subscr = $req->create_warn_subscription(
                sub ($msg) {
                    $input_hr->{'output_obj'}->warn($msg);
                }
            );

            return $req->started_promise()->then(
                sub { $input_hr->{'output_obj'}->out('Copying …') },
            )->then(
                sub { $req->done_promise() },
            )->finally( sub { undef $subscr } );
        }
    );

    Cpanel::PromiseUtils::wait_anyevent($tar_p);

    $state_obj->set( target_archive_deleted => 0 );

    return;
}

1;
