
# cpanel - Cpanel/UserManager/Storage/Upgrade.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Storage::Upgrade;

use strict;
use Carp                                   ();
use Cpanel::UserManager::Storage           ();
use Cpanel::UserManager::Storage::Versions ();
use Cpanel::Logger                         ();

=head1 NAME

Cpanel::UserManager::Storage::Upgrade

=head1 DESCRIPTION

This module manages upgrades to the Subaccount database for the current cPanel user.

=head1 FUNCTIONS

=head2 upgrade_if_needed(note => ..., quiet => ..., expire_invites => ...)

Checks the database version against a list of possible upgrades to decide if the database needs to be upgraded. If
there are upgrades to apply, they are applied and the version stored in the database is marked for that version
so the upgrade will only be applied once.

Note: There is no way to specify the user on which to operate because the user is determined
based on the current uid. Running this function as root will fail.

=head3 ARGUMENTS

note - string - (optional) If set, the note is added to the log statement for the upgrade.

quiet - boolean - (optional) If set, the log output is suppressed except in case of failures.

expire_invites - boolean - (optional) If set, also expire all pending invites sent by the affected
cPanel accounts. This is used during transfers and restores, because the invites are no longer
meaningful on the destination server.

=cut

sub upgrade_if_needed {
    my %opts = @_;
    my ( $note, $quiet, $expire_invites ) = delete @opts{qw(note quiet expire_invites)};
    Carp::croak('Unknown arguments provided to upgrade_if_needed()') if %opts;

    my $dbh = Cpanel::UserManager::Storage::dbh();

    my $logger = Cpanel::Logger->new();

    Cpanel::UserManager::Storage::Versions::create_meta_table_if_needed( dbh => $dbh, initialize => 0 );
    my ($version) = _get_version($dbh);

    # If we're not able to find an existing version number, that means we're at version zero.
    $version ||= 0;

    my $versions = Cpanel::UserManager::Storage::Versions::versions();

    my @available_upgrades = grep { $_ > $version } sort { $a <=> $b } keys %$versions;

    $logger->info( sprintf( '[%s] The current database version for this account is %d. There are %d available upgrades.', $note || '', $version, scalar(@available_upgrades) ) ) unless $quiet;

    for my $upgrade_version (@available_upgrades) {
        $logger->info("Performing upgrade to version $upgrade_version") unless $quiet;

        _do( $dbh, 'BEGIN TRANSACTION' );

        my $this_upgrade = $versions->{$upgrade_version};
        for my $statement (@$this_upgrade) {
            _do( $dbh, $statement );
        }

        # Delete and insert instead of update in case the row doesn't exist yet
        _do( $dbh, 'DELETE FROM meta WHERE key = "version"' );
        _do( $dbh, 'INSERT INTO meta (key, value) VALUES ("version", ?)', {}, $upgrade_version );

        _do( $dbh, 'COMMIT' );
    }

    if ($expire_invites) {
        _do( $dbh, 'UPDATE users SET invite_expiration=1400000000 WHERE has_invite=1' );
    }

    return;
}

sub _get_version {
    my ($dbh) = @_;
    return $dbh->selectrow_array('SELECT value FROM meta WHERE key = "version"');
}

sub _do {
    my ( $dbh, @do_args ) = @_;
    return $dbh->do(@do_args);
}

1;
