package Cpanel::SQLite::Compat;

# cpanel - Cpanel/SQLite/Compat.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# As of v58 perl always supports WAL because we
# have a new enough version of DBD::SQLite
sub upgrade_to_wal_journal_mode_if_needed {
    my ($dbh) = @_;

    my $current_journal_mode = $dbh->selectrow_arrayref("PRAGMA journal_mode");
    if ( $current_journal_mode && $current_journal_mode->[0] eq 'wal' ) {
        return 0;
    }

    $dbh->do('PRAGMA journal_mode=WAL;');
    return 1;
}

1;
