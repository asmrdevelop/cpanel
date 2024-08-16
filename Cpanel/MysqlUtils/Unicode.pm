package Cpanel::MysqlUtils::Unicode;

# cpanel - Cpanel/MysqlUtils/Unicode.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my %has_utf8mb4_cache;

#https://dev.mysql.com/doc/refman/5.5/en/charset-unicode.html
sub has_utf8mb4 {
    my ($dbh) = @_;

    die "Need DB handle!" if !$dbh->isa('DBI::db');

    if ( !exists $has_utf8mb4_cache{$dbh} ) {
        my $rows = $dbh->selectall_arrayref("SHOW CHARSET WHERE Charset = 'utf8mb4'");
        $has_utf8mb4_cache{$dbh} = @$rows ? 1 : 0;
    }

    return $has_utf8mb4_cache{$dbh};
}

1;
