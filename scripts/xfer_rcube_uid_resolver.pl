#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/xfer_rcube_uid_resolver.pl      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package scripts::xfer_rcube_uid_resolver;
use strict;

use Cpanel::Email::RoundCube::DBI;

## if invoked as a script, there is nothing in the call stack
my $invoked_as_script = !caller();
__PACKAGE__->script(@ARGV) if ($invoked_as_script);

sub script {
    ## read password from stdin, for security
    ## see positional argument list below
    my ( $package, @args ) = @_;
    my $dbpassword = scalar(<STDIN>);

    my ( $temp_dbname, $dbhost, $dbuser, $owner, $old_owner ) = @args;

    my $dbh = Cpanel::Email::RoundCube::DBI::mysql_db_connect( $temp_dbname, $dbhost, $dbuser, $dbpassword );

    return do_resolution( $dbh, $temp_dbname, $owner, $old_owner );
}

sub do_resolution {
    my ( $dbh, $temp_dbname, $owner, $old_owner ) = @_;

    my $src_dbh = $dbh->clone( { database => $temp_dbname } );

    my $dest_dbh = $dbh->clone( { database => 'roundcube' } );

    ## note: &uid_solver uses introspective techniques that the DBD sqlite package
    ##   is not really ready for; otherwise, uid_solver could be used to port
    ##   a sqlite database back into mysql with only a change to the $src_dbh!

    ## at this point, src data is in a temp mysql, and schema is "up to date" relative to dest
    ## now, massage the potentially colliding UIDs into dest via $dbh->last_insert_id
    my ( $res, $msg ) = Cpanel::Email::RoundCube::DBI::uid_solver( $src_dbh, $dest_dbh, $owner, $old_owner );

    $src_dbh->disconnect();
    $dest_dbh->disconnect();

    return;
}

1;
