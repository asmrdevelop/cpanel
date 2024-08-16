package Cpanel::Dsync::CpsrvdClient;

# cpanel - Cpanel/Dsync/CpsrvdClient.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Dsync::Client

=head1 DESCRIPTION

This module implements a client for dsync streaming.

=cut

#----------------------------------------------------------------------

use Promise::XS ();

use Cpanel::Dovecot::Utils ();
use Cpanel::TempFH         ();

use constant _SYNC_TIMEOUT => 7200;    # 2 hours

# Accessed from tests.
our ( %_CLIENT_SCRIPT, @_BACKUP_NEEDS );

BEGIN {
    @_BACKUP_NEEDS = (
        'execer',
        'peer',
        'authn_username',
        'api_token',
        'account_name',
        'remote_account_name',
    );

    %_CLIENT_SCRIPT = (
        cpanel => '/usr/local/cpanel/bin/dsync_cpsrvd_client_cpanel',
        whm    => '/usr/local/cpanel/bin/dsync_cpsrvd_client_whm',
    );
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 sync_to_local(%OPTS)

One-way-dsyncs a remote mail account to the local account with the
same name. At the end, the local account’s mail will be a superset
of the remote account’s.

%OPTS are:

=over

=item * C<execer> - A L<Cpanel::Async::Exec> instance.

=item * C<application> - Either C<whm> or C<cpanel>.

=item * C<peer> - Either a hostname or an IP address for the remote cPanel
& WHM server.

=item * C<authn_username> - The username to authenticate with cpsrvd.

=item * C<api_token> - The API token for C<username>.

=item * C<account_name> - The name of the email account in question.
This can be a system account name.

=item * C<remote_account_name> - Same as C<account_name>, B<unless>
that value is a system account name, in which case it must be
C<_mainaccount@$domain>, where C<$domain> is one of C<account_name>’s
domains.

=back

This returns a promise that resolves once the synchronization has
finished. Any failures cause that promise to be rejected.

=cut

sub sync_to_local (%opts) {

    # -R = pull from remote to local
    #
    # “-1”, per dsync(1), should be unneeded, but without it we get
    # errors like:
    #
    #   Mailbox INBOX sync: mailbox_delete failed: INBOX can't be deleted.
    #
    # The -1 flag is deprecated in 2.3.18 with the `backup` arg, so we use
    # `sync` as the docs suggest this is what is needed.
    #
    # Also, despite that dsync(1) describes “backup” as a destructive backup
    # (i.e., “If there are any changes in the destination they will be
    # deleted”), the actual behavior is non-destructive; the destination
    # retains whatever it has uniquely. Note that as of 11.104, this behavior
    # may or may not still be accurate, but we are now using sync which is
    # non-destructive anyway.
    #
    # https://wiki.dovecot.org/Tools/Doveadm/Sync

    return _sync_or_backup( [ 'sync', '-R', '-1' ], %opts );
}

sub sync_to_remote (%opts) {

    # See notes in sync_to_local().
    #
    return _sync_or_backup( [ 'sync', '-1' ], %opts );
}

sub _sync_or_backup ( $cmd_ar, %opts ) {
    my @missing = grep { !$opts{$_} } @_BACKUP_NEEDS;
    die "needs: @missing" if @missing;

    my $dsync_bin = Cpanel::Dovecot::Utils::dsync_bin();

    my $application = $opts{'application'} // die 'need application';

    my $script_path = $_CLIENT_SCRIPT{$application} // do {
        die "Bad application: “$application”";
    };

    my $stderr = Cpanel::TempFH::create();

    my $run = $opts{'execer'}->exec(
        program => $dsync_bin,
        args    => [
            @$cmd_ar,

            '-u' => $opts{'account_name'},

            $script_path,
            $opts{'peer'},
            @opts{ 'authn_username', 'api_token' },
            $opts{'remote_account_name'},
        ],
        stderr => $stderr,
        $opts{'timeout'} ? ( timeout => $opts{'timeout'} ) : (),
    );

    my $d = Promise::XS::deferred();

    $run->child_error_p()->then(
        sub ($child_error) {
            if ($child_error) {
                require Cpanel::ChildErrorStringifier;
                my $ces = Cpanel::ChildErrorStringifier->new( $child_error, $dsync_bin );

                my $err = $ces->to_exception();

                sysseek $stderr, 0, 0;

                $err->set(
                    stderr => do { local $/; <$stderr> }
                );

                $d->reject($err);
            }
            else {

                # On success we assume that the subprocess’s STDERR
                # is unneeded. Hopefully that’s a safe assumption?

                $d->resolve();
            }
        },

        sub ($why) { $d->reject($why) },
    );

    return $d->promise();
}

1;

