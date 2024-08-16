
# cpanel - Cpanel/Hulk/Admin/DB.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Hulk::Admin::DB;

use strict;
use warnings;

=head1 NAME

Cpanel::Hulk::Admin::DB

=head1 SYNOPSIS

    use Cpanel::Hulk::Admin::DB ();
    my $dbh = Cpanel::Hulk::Admin::DB::get_dbh();

=head1 DESCRIPTION

This module manages the creation of the database handles to the cPHulk sqlite database.

The primary use for this module, is the C<Cpanel::Hulk::Admin::DB::get_dbh()> function,
which returns a DBI handle that can be used to interact with the cPHulk sqlite DB.

=cut

use Cpanel::DBI::SQLite  ();
use Cpanel::SQLite::Busy ();
use Cpanel::Config::Hulk ();

=head1 FUNCTIONS

=head2 get_dbh($extra_args_hr)

Returns a DBI Database Handle object for the database connection, suitable for passing in to the other
functions in this module. Any C<$extra_args_hr> specified are passed on to C<Cpanel::DBI::SQLite->connect()>
call.

=cut

sub get_dbh {
    my $extra_args_hr = shift;

    my $dbh = eval { _initialize_dbh($extra_args_hr); };
    return $dbh;
}

=head2 initialize_db($force)

Initializes the cPHulk SQLite DB. If C<$force> is true, then the existing tables are dropped
before they are recreated with the right structure.

=cut

sub initialize_db {
    my $force = shift;

    my $dbh = _initialize_dbh();
    $dbh->do('PRAGMA journal_mode = WAL;');

    _create_auths_tbl( $dbh, $force );
    _create_ip_lists_tbl( $dbh, $force );
    _create_known_netblocks_tbl( $dbh, $force );
    _create_login_track_tbl( $dbh, $force );
    _create_config_track_tbl( $dbh, $force );

    return $dbh;
}

=head2 integrity_check()

Performs an integrity check on the cPHulk SQLite DB.

This call B<WILL> die on error, the caller is responsible for
how these exception are handled.

=cut

sub integrity_check {
    my $dbh = _initialize_dbh();

    $dbh->sqlite_busy_timeout( Cpanel::SQLite::Busy::TIMEOUT() );

    # If the integrity_check call fails, then this will throw an odd 'SQLITE_TOOBIG' error
    # but if the call succeeds we still get the expected 'ok' back.
    my $result = $dbh->selectcol_arrayref('PRAGMA integrity_check;');
    if ( $result->[0] eq 'ok' ) {

        # Since the integrity_check is not robust enough to rely on solely,
        # we also go over all of the tables and make sure none of them are corrupt.
        foreach my $table (qw(auths ip_lists known_netblocks login_track)) {
            $dbh->selectcol_arrayref("SELECT COUNT(*) FROM $table;");
        }
    }

    return 1;
}

# The config_track table is used for tracking when parts of the configuration
# where last updated.
#
# Current we only use this to determine when the last time we updated the ips
# for the country white and blacklists with the “last_update_country_ips_time” key.
#
sub _create_config_track_tbl {
    my ( $dbh, $force ) = @_;

    $dbh->do('DROP TABLE IF EXISTS `config_track`;') if $force;

    $dbh->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS `config_track` (
  `ENTRY` CHAR(128) NOT NULL,
  `VALUE` CHAR(128) NOT NULL,
  PRIMARY KEY (`ENTRY`)
);
END_OF_SQL
    );

    return 1;
}

sub _create_auths_tbl {
    my ( $dbh, $force ) = @_;

    $dbh->do('DROP TABLE IF EXISTS `auths`;') if $force;

    $dbh->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS `auths` (
  `SERVER` CHAR(128) NOT NULL,
  `USER` CHAR(128) NOT NULL,
  `PASS` CHAR(128) NOT NULL,
  PRIMARY KEY (`SERVER`,`USER`)
);
END_OF_SQL
    );

    return 1;
}

sub _create_ip_lists_tbl {
    my ( $dbh, $force ) = @_;

    $dbh->do('DROP TABLE IF EXISTS `ip_lists`;') if $force;

    $dbh->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS `ip_lists` (
  `STARTADDRESS` VARBINARY(16) NOT NULL DEFAULT '',
  `ENDADDRESS` VARBINARY(16) NOT NULL DEFAULT '',
  `TYPE` INT(1) NOT NULL DEFAULT '0',
  `COMMENT` CHAR(255) DEFAULT NULL,
  UNIQUE (`STARTADDRESS`,`ENDADDRESS`) ON CONFLICT REPLACE
);
END_OF_SQL
    );

    return 1;
}

sub _create_known_netblocks_tbl {
    my ( $dbh, $force ) = @_;

    $dbh->do('DROP TABLE IF EXISTS `known_netblocks`;') if $force;

    $dbh->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS `known_netblocks` (
  `USER` CHAR(128) NOT NULL,
  `STARTADDRESS` VARBINARY(16) NOT NULL DEFAULT '',
  `ENDADDRESS` VARBINARY(16) NOT NULL DEFAULT '',
  `LOGINTIME` DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
  UNIQUE (`USER`,`STARTADDRESS`,`ENDADDRESS`) ON CONFLICT REPLACE
);
END_OF_SQL
    );

    $dbh->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS `LOGINTIME_index` ON known_netblocks(LOGINTIME);
END_OF_SQL
    );

    $dbh->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS `USER_index` ON known_netblocks(USER);
END_OF_SQL
    );

    return 1;
}

sub _create_login_track_tbl {
    my ( $dbh, $force ) = @_;

    $dbh->do('DROP TABLE IF EXISTS `login_track`;') if $force;

    $dbh->do(
        <<END_OF_SQL
CREATE TABLE IF NOT EXISTS `login_track` (
  `USER` CHAR(128) NOT NULL,
  `ADDRESS` VARBINARY(16) DEFAULT NULL,
  `SERVICE` CHAR(64) DEFAULT NULL,
  `TYPE` INT(1) DEFAULT NULL,
  `LOGINTIME` DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
  `EXPTIME` DATETIME NOT NULL DEFAULT '0000-00-00 00:00:00',
  `NOTES` TEXT,
  `AUTHSERVICE` CHAR(64) DEFAULT NULL,
  `AUTHTOKEN_HASH` CHAR(86) DEFAULT ''
);
END_OF_SQL
    );

    $dbh->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS `EXPTIME_ADDRESS_index` ON login_track(EXPTIME, ADDRESS);
END_OF_SQL
    );

    $dbh->do(
        <<END_OF_SQL
CREATE INDEX IF NOT EXISTS `EXPTIME_USER_SERVICE_index` ON login_track(EXPTIME, USER, SERVICE);
END_OF_SQL
    );

    return 1;
}

sub _initialize_dbh {
    my $extra_args_hr = shift // {};
    my $database      = Cpanel::Config::Hulk::get_sqlite_db();

    if ( !-e $database ) {
        open my $fh, '>', $database or die "Unable to create DB: $!\n";    #touch
        close $fh;
        chmod 0600, $database or die "Unable to set permissions on DB: $!\n";
    }

    my $dbi_opts = {
        %{$extra_args_hr},
        'db' => $database
    };

    my $dbh = Cpanel::DBI::SQLite->connect($dbi_opts);
    $dbh->do('PRAGMA cache_size = 8000');
    $dbh->do('PRAGMA temp_store = 2');
    return $dbh;
}

1;
