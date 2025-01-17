package Cpanel::DBI::SQLite::Error;

# cpanel - Cpanel/DBI/SQLite/Error.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#cf. https://sqlite.org/c3ref/c_abort.html

#NOTE: Not all of the below are used.
#The unused ones just seem like generally useful codes to have that we might
#want to check for.

use constant {
    SQLITE_ERROR      => 1,
    SQLITE_INTERNAL   => 2,
    SQLITE_PERM       => 3,
    SQLITE_ABORT      => 4,
    SQLITE_BUSY       => 5,
    SQLITE_LOCKED     => 6,
    SQLITE_NOMEM      => 7,
    SQLITE_READONLY   => 8,
    SQLITE_INTERRUPT  => 9,
    SQLITE_IOERR      => 10,
    SQLITE_CORRUPT    => 11,
    SQLITE_NOTFOUND   => 12,
    SQLITE_FULL       => 13,
    SQLITE_CANTOPEN   => 14,
    SQLITE_PROTOCOL   => 15,
    SQLITE_EMPTY      => 16,
    SQLITE_SCHEMA     => 17,
    SQLITE_TOOBIG     => 18,
    SQLITE_CONSTRAINT => 19,
    SQLITE_MISMATCH   => 20,
    SQLITE_MISUSE     => 21,
    SQLITE_NOLFS      => 22,
    SQLITE_AUTH       => 23,
    SQLITE_FORMAT     => 24,
    SQLITE_RANGE      => 25,
    SQLITE_NOTADB     => 26,
    SQLITE_NOTICE     => 27,
    SQLITE_WARNING    => 28,
    SQLITE_ROW        => 100,
    SQLITE_DONE       => 101,
};

sub get_name_for_error {
    my ($num) = @_;

    for my $k ( keys %Cpanel::DBI::SQLite::Error:: ) {
        next if $k !~ m<\ASQLITE_>;
        my $cr = __PACKAGE__->can($k) or next;

        return $k if $cr->() == $num;
    }

    return undef;
}

1;
