package Cpanel::DBI::SQLite;

# cpanel - Cpanel/DBI/SQLite.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Instantiate as you would with DBI, except the argument to connect()
# is a hashref of key/value pairs.
#----------------------------------------------------------------------

use strict;

use parent qw( Cpanel::DBI::ConnectUsesHash );

use Cpanel::Exception                ();
use Cpanel::Validate::FilesystemPath ();

my @forbidden_dbname_chars = (';');

sub connect_memory {
    my ( $class, $attrs_hr ) = @_;

    return $class->dbi_connect(
        "dbi:SQLite:dbname=:memory:",
        undef,
        undef,
        { RaiseError => 1, $attrs_hr ? %$attrs_hr : () },
    );
}

sub _connect {
    my ( $class, $username, $password, $attrs_hr ) = @_;

    #Normalized in ConnectUsesHash
    my $dbname = $attrs_hr->{'database'};

    Cpanel::Validate::FilesystemPath::die_if_any_relative_nodes($dbname);

    if ( substr( $dbname, length($dbname) - 1 ) eq '/' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'An [asis,SQLite] database name may not end with the character “[_1]”.', ['/'] );
    }

    #Ensure that ":memory:" is a file, not the special thing that DBD::SQLite
    #looks for to create an in-memory DB.
    if ( substr( $dbname, 0, 1 ) ne '/' ) {
        substr( $dbname, 0, 0, './' );
    }

    #This is a DBI::SQLite limitation: it can't handle semicolons in a database name.
    my $check = '[' . join( q<>, @forbidden_dbname_chars ) . ']';
    if ( $dbname =~ m<$check> ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'A [asis,SQLite] database name may not contain the following [numerate,_1,character,characters]: [join,~, ,_2]', [ scalar(@forbidden_dbname_chars), \@forbidden_dbname_chars ] );
    }

    # TODO: report filename and permissions errors with something
    # that can be understood
    return $class->dbi_connect(
        "dbi:SQLite:dbname=$dbname",
        $username,
        $password,

        #TODO: Cpanel::DBI should set RaiseError on by default;
        #subclasses should not have that responsibility.
        { RaiseError => 1, %$attrs_hr },
    );
}

package Cpanel::DBI::SQLite::db;

use Cpanel::DBI ();    # PPI USE OK - In the other driver modules Cpanel::DBI::SQLite should be setting it as a base class but it's not here.

use parent qw( -norequire Cpanel::DBI::db );

package Cpanel::DBI::SQLite::st;

use Cpanel::DBI ();    # PPI USE OK - In the other driver modules Cpanel::DBI::SQLite should be setting it as a base class but it's not here.

use parent qw( -norequire Cpanel::DBI::st );

1;
