package Cpanel::APNS::Mail::DB::Sqlite;

# cpanel - Cpanel/APNS/Mail/DB/Sqlite.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

use Cpanel::APNS::Mail::Config ();

=encoding utf-8

=head1 NAME

Cpanel::APNS::Mail::DB::Sqlite

=head1 SYNOPSIS

    # Will rebuild the APNS sqlite db if it has become corrupt
    my $dbh = Cpanel::APNS::Mail::DB::Sqlite->dbconnect();

    # Will NOT rebuild the APNS sqlite db
    $dbh = Cpanel::APNS::Mail::DB::Sqlite->dbconnect_no_rebuild();

=head1 DESCRIPTION

This module manages the creation of the database handles to the APNS sqlite database.
It also handles the creation and recreation of the APNS database if it hasn't been created yet
or has become corrupt.

NOTE: We use SQLite as the backend to APNS now. Please do NOT use the same dbh after a fork. Get a new dbh.

=head1 FUNCTIONS


=cut

sub _PATH {
    return Cpanel::APNS::Mail::Config::DB_FILE();
}

use constant {
    _SCHEMA_NAME => 'mail_apns',

    #Schema versions should be integers from now on
    #and increment by one each time. See AutoRebuildSchemaBase.
    _SCHEMA_VERSION => 1,
};

1;
