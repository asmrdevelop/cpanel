package Cpanel::BandwidthDB::Schema;

# cpanel - Cpanel/BandwidthDB/Schema.pm              Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module manages the schema (i.e., the tables, indexes, etc) for
# the bandwidth DB. Do NOT use this module for updates to the DB other
# than schema changes!
#
# Note that, for production use, you may want to call into
# Cpanel::BandwidthDB::Upgrade instead. That module calls into this one
# and also calls into any ancillary modules that may be part of schema
# updates.
#
# Schema versions:
#
#   1 - the original SQLite setup
#
#   2 - Added “metadata” table. Upgrades also include RRD imports.
#----------------------------------------------------------------------

use strict;

use Cpanel::BandwidthDB::Base      ();
use Cpanel::BandwidthDB::Constants ();

sub upgrade_schema {
    my ( $dbh, $to_version ) = @_;

    my $save_name = "update_to_schema_$to_version";

    $dbh->do("SAVEPOINT $save_name");

    __PACKAGE__->can("_v$to_version")->( $dbh, $to_version );
    _write_schema_version( $dbh, $to_version );

    $dbh->do("RELEASE SAVEPOINT $save_name");

    return 1;
}

sub _write_schema_version {
    my ( $dbh, $to_version ) = @_;

    #It is assumed that we are already in a transaction.
    #Checking $dbh->{'AutoCommit'} doesn’t seem to work, though...

    $dbh->do('DELETE FROM version');
    $dbh->do( 'INSERT INTO version VALUES (?)', undef, $to_version );

    return;
}

sub _v3 {

    # We currently don't need to do any updates here so this is a noop.
    # In this version (as of May 2017) of the schema we just need to update the schema version
    # as all the changes are backup/restore related.

    return;
}

sub _v2 {
    my $dbh = shift;

    $dbh->do('CREATE TABLE metadata (key string primary key, value string)');

    return;
}

sub create_schema {
    my ( $dbh, $version ) = @_;

    $dbh->do('BEGIN TRANSACTION;');
    $dbh->do('CREATE TABLE version (version real primary key)');
    _write_schema_version( $dbh, 1 );

    #This could actually define the “daily” data as a view of the “hourly” since
    #we keep both around indefinitely. Because of the month translation, though,
    #that ends up being pretty slow.
    #
    #TODO: Refactor these two C::BwDB::Base methods to be named as public.
    #
    for my $interval ( Cpanel::BandwidthDB::Base->_INTERVALS() ) {
        my $table   = Cpanel::BandwidthDB::Base->_interval_table($interval);
        my $table_q = $dbh->quote_identifier($table);

        $dbh->do(
            qq<
            CREATE TABLE $table_q
            (
                domain_id       integer,
                protocol        string,
                unixtime        integer,
                bytes           integer,
                primary key     (domain_id, protocol, unixtime)
            )
        >
        );

        for my $idx (qw( unixtime  protocol  domain_id )) {
            my $idx_table_q = $dbh->quote_identifier( join( '_', $table, $idx, 'index' ) );

            $dbh->do(
                qq<
                CREATE INDEX $idx_table_q ON $table_q (unixtime)
            >
            );
        }
    }

    $dbh->do(
        q<
        CREATE TABLE domains
        (
            name    string,
            id      integer primary key
        )
    >
    );

    #Everything needs this, so it might as well be part of the schema initialization.
    $dbh->do( 'INSERT INTO domains (name) VALUES (?)', undef, $Cpanel::BandwidthDB::Constants::UNKNOWN_DOMAIN_NAME );

    $dbh->do('END TRANSACTION;');
    for my $upgrade_to ( 2 .. $version ) {
        upgrade_schema( $dbh, $upgrade_to );
    }

    return;
}

1;
