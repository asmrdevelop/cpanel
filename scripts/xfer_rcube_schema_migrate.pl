#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/xfer_rcube_schema_migrate.pl    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package scripts::xfer_rcube_schema_migrate;
use strict;

use DBI ();

use Cpanel::Email::RoundCube::DBI ();

## if invoked as a script, there is nothing in the call stack
my $invoked_as_script = !caller();
__PACKAGE__->script(@ARGV) if ($invoked_as_script);

sub script {
    ## read password from stdin, for security
    ## see positional argument list below
    my ( $package, @args ) = @_;
    my $dbpassword = scalar(<STDIN>);

    my ( $dbname, $dbhost, $src_version, $dest_version, $dbuser ) = @args;

    ## SOMEDAY: need RaiseError off, until we are certain the schema in the database is the
    ##   same version as the Roundcube that is installed
    ## PrintError is off as well; the temporary database, as it is generated via pkgacct's
    ##   mysqldump, will not have the messages, cache, or session table; the various
    ##   schema migration scripts on these tables will spam the whm xfer screen
    my $dbh = Cpanel::Email::RoundCube::DBI::mysql_db_connect(
        $dbname, $dbhost, $dbuser, $dbpassword,
        { RaiseError => 0, PrintError => 0 }
    );

    my $rv = do_migration( $dbh, $src_version, $dest_version );

    $dbh->disconnect();

    unless ($rv) {
        die "Roundcube schema migration failed for temp database '$dbname'";
    }
}

#NOTE: The $src_dbh is assumed to be USEing the correct DB!
sub do_migration {
    my ( $src_dbh, $src_version, $dest_version ) = @_;

    ## SOMEDAY: there is a trade-off here between communicating the $src_version via
    ##   parameters, and computing the $src_version from reading the cp_schema_table;
    ##   at the moment, I feel more secure in sending it in; eventually, might modify
    ##   pkgacct to include cp_schema_version in the mysqldump, and additionally to
    ##   ensure the table exists here

    #NOTE: Should this also call Cpanel::Email::RoundCube::write_version_file()?
    #(It would need to pass in the version as a parameter.)

    my $opts = { installed_version => $src_version };
    return Cpanel::Email::RoundCube::DBI::ensure_schema_update( $src_dbh, 'mysql', $dest_version, $opts );
}

1;
