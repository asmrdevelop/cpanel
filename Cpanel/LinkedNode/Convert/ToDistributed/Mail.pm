package Cpanel::LinkedNode::Convert::ToDistributed::Mail;

# cpanel - Cpanel/LinkedNode/Convert/ToDistributed/Mail.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::ToDistributed::Mail

=head1 DESCRIPTION

This module implements most parts of the logic to convert a user whose mail
is local to delegate its mail to one of the server’s child nodes.

=cut

# One-liner for ease of testing:
# perl -MCpanel::Output::Formatted::Terminal -MCpanel::LinkedNode::Convert::ToDistributed::Mail -e'Cpanel::LinkedNode::Convert::ToDistributed::Mail::convert( worker_alias => "mail2", username => "mail2defer", output_obj => Cpanel::Output::Formatted::Terminal->new() )'

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::ConfigFiles                                       ();
use Cpanel::Dovecot::Utils                                    ();
use Cpanel::LinkedNode::Convert::ArchiveDirToNode             ();
use Cpanel::LinkedNode::Convert::Common::Mail::ToRemote       ();
use Cpanel::LinkedNode::Convert::TaskRunner                   ();
use Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend ();
use Cpanel::LinkedNode::Convert::ToDistributed::Mail::State   ();
use Cpanel::LinkedNode::Convert::ToDistributed::Mail::Sync    ();
use Cpanel::SafeRun::Object                                   ();
use Cpanel::UserLock                                          ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 convert( %OPTS )

Converts an existing account whose mail is local to offload its mail to
a worker (child) node.

%OPTS are:

=over

=item * C<username> - The account’s username.

=item * C<worker_alias> - The worker node’s alias.

=item * C<output_obj> - A L<Cpanel::Output> instance that will receive
notifications while this conversion is in process.

=back

The major steps that this takes are:

=over

=item 1. Create an archive of the account. This archive should include just
those parts needed for this conversion.

=item 2. Send the archive to the child node.

=item 3. Restore that archive on the child node.

=item 4. Copy the user’s home directory mail files (e.g., F<~/etc>) to the
child node.

=item 5. Normalize the child node user’s email configuration (e.g.,
filesystem permissions).

=item 6. Update the user’s DNS zones so that all C<mail.*> subdomains point to
the child node and all MX records that pointed to the local node now point
to the child node.

=item 7. Create an API token for the user on the child node, and assign that
as the local user’s C<Mail> worker token.

=back

Nothing is returned.

B<IMPORTANT:> This does B<NOT> currently do a final synchronization between
the local and remote mailboxes. That will be necessary for this logic to suit
the use case of converting an existing account, but the logic as-is suffices
for restoring an account.

=cut

sub convert (@opts_kv) {
    return _convert_or_restore(
        [qw( username  worker_alias  output_obj )],
        @opts_kv,
    );
}

=head2 restore( %OPTS )

Like C<convert()> but:

=over

=item * Requires a C<cpmove_path> to be given. That local archive is what is
sent over and restored on the remote rather than a new, locally-created
archive.

=item * Does not copy anything from the local home directory to the
child node.

=back

This suits the use case of restoring a distributed-mail backup to
distributed-mail configuration.

=cut

sub restore (@opts_kv) {
    return _convert_or_restore(
        [qw( username  worker_alias  cpmove_path  output_obj )],
        @opts_kv,
    );
}

sub _convert_or_restore ( $req_ar, %opts ) {
    my @missing = grep { !length $opts{$_} } @$req_ar;
    die "need: @missing" if @missing;

    my %input = %opts{@$req_ar};

    my $user_lock = Cpanel::UserLock::create_shared_or_die( $input{'username'} );

    my $is_restore = !!$opts{'cpmove_path'};

    my $state = Cpanel::LinkedNode::Convert::ToDistributed::Mail::State->new();
    $state->set(
        local_cpmove_path      => $opts{'cpmove_path'},
        target_archive_deleted => 0,
    );

    my $tar_backup_xform;

    if ($is_restore) {

        # Replace the first filesystem path with “cpmove-$username”.
        $tar_backup_xform = "s,^[^/]+,cpmove-$opts{'username'},x";
    }

    $state->set( tar_backup_transform => $tar_backup_xform );

    my @main_steps = (
        {
            label => locale()->maketext('Verifying child node capabilities …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__verify_child_node,
        },
        {
            label => locale()->maketext('Determining required [asis,DNS] updates …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__determine_dns_updates,
        },
    );

    if ( !$is_restore ) {
        push @main_steps, {
            label => locale()->maketext('Creating the local mail-only account archive …'),
            code  => \&_pkgacct,
        };
    }

    push @main_steps, (
        {
            label      => locale()->maketext('Copying the account archive to the child node …'),
            code       => \&_copy_archive,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__copy_archive_to_target,
            undo_label => sub {
                if ( $state->get('target_archive_deleted') ) {

                    # There seems no need to say, “we aren’t going to delete
                    # the remote account archive because the restoration
                    # already deleted it.”
                    return undef;
                }

                return locale()->maketext('Deleting the account archive on the child node …');
            },
        },
        {
            label => locale()->maketext('Determining if the account already exists on the child node …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__determine_preexistence,
        },
        {
            label      => locale()->maketext('Restoring the account on the child node …'),
            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__target_restore,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__target_restore,
            undo_label => sub {
                if ( !$state->get('target_listaccts_hr') ) {
                    return locale()->maketext('Deleting the account on the child node …');
                }

                return locale()->maketext('Because the [asis,cPanel] account already existed on the child node, the system will not delete the child account.');
            },
        },
    );

    if ( !$is_restore ) {
        push @main_steps, {
            label => locale()->maketext('Copying the mail-related home directory items to the child node …'),
            code  => \&_send_mail_parts_of_homedir,
        };
    }

    push @main_steps, (
        {
            label => locale()->maketext('Configuring the child account …'),
            code  => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__configure_new_child_account,
        },
        {
            label      => locale()->maketext('Updating [asis,DNS] …'),
            code       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::step__update_dns,
            undo       => \&Cpanel::LinkedNode::Convert::Common::Mail::ToRemote::undo__update_dns,
            undo_label => locale()->maketext('Undoing [asis,DNS] updates …'),
        },

        {
            label      => locale()->maketext('Enabling direct mail routing to the child node …'),
            code       => \&Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend::step__set_up_manual_mx,
            undo       => \&Cpanel::LinkedNode::Convert::ToDistributed::Mail::Backend::undo__set_up_manual_mx,
            undo_label => locale()->maketext('Reverting direct mail routing …'),
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

        {
            label => locale()->maketext('Terminating local mail sessions …'),
            code  => \&_kick,
        },
        {
            label => locale()->maketext('Synchronizing mail …'),
            code  => \&_sync_mail,
        },
        {
            label => locale()->maketext('Deleting local mail …'),
            code  => \&_delete_local_mail,
        },
    );

    Cpanel::LinkedNode::Convert::TaskRunner->run(
        $opts{'output_obj'},
        \@main_steps,
        \%input,
        $state,
    );

    $opts{'output_obj'}->success( locale()->maketext( 'Conversion of the account “[_1]” succeeded.', $opts{'username'} ) );

    return;
}

#----------------------------------------------------------------------
# STEPS (not necessarily in order!):

sub _delete_local_mail ( $input_hr, $state_obj ) {

    my $output_obj = $input_hr->{'output_obj'};

    # It would be more performant to expunge mail during the same event
    # loop run as in _sync_mail(), but would we do that via fork/exec,
    # doveadm protocol, or Dovecot’s HTTP API? For now let’s prefer the
    # simplest solution, then we can iterate as needs dicate.

    my $delete_local_hr = $state_obj->get('delete_local');

    for my $acctname ( keys %$delete_local_hr ) {
        my $indent = $output_obj->create_indent_guard();

        my ( $log_level, $log_msg );

        if ( $delete_local_hr->{$acctname} ) {
            try {
                Cpanel::Dovecot::Utils::expunge_mailbox_messages(
                    account => $acctname,
                    query   => 'ALL',
                    mailbox => '*',
                );

                # doveadm expunge treats * as only top-level mailboxes and *.*
                # as only sub-level mailboxes so we have to run two queries to
                # remove mail from both the main inbox and the sub-level Sent,
                # Spam, etc …
                Cpanel::Dovecot::Utils::expunge_mailbox_messages(
                    account => $acctname,
                    query   => 'ALL',
                    mailbox => '*.*',
                );

                $log_msg = locale()->maketext('Local mail deleted.');
            }
            catch {
                $log_level = 'warn';
                $log_msg   = locale()->maketext( 'The system failed to delete local mail because of an error: [_1]', $_ );
            };
        }
        else {
            $log_msg = locale()->maketext('This account’s mail synchronization failed. Because of this, the system will leave the account’s mail in place.');
        }

        $log_level ||= 'info';

        $output_obj->$log_level("$acctname: $log_msg");
    }

    return;
}

sub _sync_mail ( $input_hr, $state_obj ) {
    my $node_obj = $state_obj->get('target_node_obj');

    my $indent = $input_hr->{'output_obj'}->create_indent_guard();

    my $local_hr = Cpanel::LinkedNode::Convert::ToDistributed::Mail::Sync::sync(
        %{$input_hr}{ 'username', 'output_obj' },

        hostname  => $node_obj->hostname(),
        api_token => $node_obj->api_token(),
    );

    $state_obj->set( 'delete_local', $local_hr );

    return;
}

sub _kick ( $input_hr, $ ) {
    Cpanel::Dovecot::Utils::kick_all_sessions_for_cpuser( $input_hr->{'username'} );

    return;
}

sub _pkgacct ( $input_hr, $state_obj ) {
    require File::Temp;
    my $dir = File::Temp::tempdir( CLEANUP => 1 );

    Cpanel::SafeRun::Object->new_or_die(
        program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/pkgacct",
        args    => [
            $input_hr->{'username'},
            $dir,

            # Tell pkgacct to leave the work dir as-is; we’ll stream
            # that dir to the remote via tar.
            '--incremental',

            # Things to omit because a Mail child doesn’t need it:
            '--skipacctdb',
            '--skipapitokens',
            '--skipauthnlinks',
            '--skipbwdata',
            '--skipdnssec',
            '--skipdnszones',
            '--skipftpusers',
            '--skiphomedir',
            '--skiplinkednodes',
            '--skiplogs',
            '--skipresellerconfig',
            '--skipshell',
            '--skipvhosttemplates',
            '--skipcron',
        ],
    );

    my $work_dir_name = "cpmove-$input_hr->{'username'}";

    $state_obj->set(
        work_dir_name     => $work_dir_name,
        local_cpmove_path => "$dir/$work_dir_name",
    );

    return;
}

sub _copy_archive ( $input_hr, $state_obj ) {
    my $remote_dir = Cpanel::LinkedNode::Convert::ArchiveDirToNode::send(
        node_obj         => $state_obj->get('target_node_obj'),
        archive_dir_path => $state_obj->get('local_cpmove_path'),
        tar_transform    => $state_obj->get('tar_backup_transform'),
    );

    # Either the passed-in cpmove path ends with cpmove-$username, or
    # we tar_transform’ed it into existence. Either way, this is what
    # we’ll have on the remote.
    $state_obj->set( target_cpmove_path => "$remote_dir/cpmove-$input_hr->{'username'}" );

    return;
}

sub _send_mail_parts_of_homedir ( $input_hr, $state_obj ) {
    require Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedirMail;
    Cpanel::LinkedNode::Convert::ToDistributed::Mail::SendHomedirMail::send(
        node_obj => $state_obj->get('target_node_obj'),
        username => $input_hr->{'username'},
    );

    return;
}

1;
