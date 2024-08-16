package Cpanel::EximStats::DB::Sqlite;

# cpanel - Cpanel/EximStats/DB/Sqlite.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

=encoding utf-8

=head1 NAME

Cpanel::EximStats::DB::Sqlite

=head1 SYNOPSIS

    # Will rebuild the eximstats sqlite db if it has become corrupt
    my $dbh = Cpanel::EximStats::DB::Sqlite->dbconnect();

    # Will NOT rebuild the eximstats sqlite db
    $dbh = Cpanel::EximStats::DB::Sqlite->dbconnect_no_rebuild();

=head1 DESCRIPTION

This module manages the creation of the database handles to the eximstats sqlite database.
It also handles the creation and recreation of the eximstats database if it hasn't been created yet
or has become corrupt.

NOTE: We use SQLite as the backend to EximStats now. Please do NOT use the same dbh after a fork. Get a new dbh.

=head1 FUNCTIONS


=cut

use Cpanel::LoadModule ();
use Try::Tiny;

use Cpanel::EximStats::Constants ();

=head2 get_status()

Returns a hash reference:

=over

=item * C<status> - one of:

=over

=item * C<active> - The DB is available and up-to-date as normal.

=item * C<importing> - The DB is available, but we’re importing data.

=item * C<upcp> - The DB is unavailable because cPanel & WHM is updating.

=back

It is possible for cPanel & WHM to be updating but for the DB
to be available as well; in this instance, C<status> will be C<active>,
not C<upcp>, even though C<upcp> is running.

=item * C<since> - An ISO-formatted date that indicates the start of
the current state. Only defined if C<status> is not C<active>.

=item * C<pid> - The ID of the process that’s responsible for the current
state. Only defined if C<status> is C<importing>.

=back

If the DB fails to open otherwise (e.g., it’s just missing, period) then
an exception is thrown.

=cut

sub get_status {
    my ( $status, $since, $pid );

    try {

        #If the DB is missing here, we want to report that rather than
        #rebuilding, as rebuilding won’t trigger a re-import of the data.
        __PACKAGE__->new_without_rebuild();

        Cpanel::LoadModule::load_perl_module('Cpanel::EximStats::ImportInProgress');
        my $in_prog = Cpanel::EximStats::ImportInProgress::read_if_exists();
        if ($in_prog) {
            $status = 'importing';
            ( $since, $pid ) = @{$in_prog}{qw( start_time  pid )};
        }
        else {
            $status = 'active';
        }
    }
    catch {
        my $err = $_;
        Cpanel::LoadModule::load_perl_module('Cpanel::Update::InProgress');
        Cpanel::LoadModule::load_perl_module('Cpanel::Time::ISO');

        if ( Cpanel::Update::InProgress->is_on() ) {
            $status = 'upcp';
            $since  = Cpanel::Time::ISO::unix2iso( ( stat _ )[10] );
        }
        else {

            #There shouldn’t be a DB connect error unless upcp is running.
            #If we got here, then that’s worth complaining about loudly.
            local $@ = $err;
            die;
        }
    };

    return {
        status => $status,
        since  => $since,
        pid    => $pid,
    };
}

sub _create_db_post {
    my ( $self, %OPTS ) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::SafeRun::Object');
    Cpanel::LoadModule::load_perl_module('Cpanel::ConfigFiles');

    # We only want to reimport when there was an old DB that was corrupted.
    if ( $OPTS{had_old_db} ) {
        my $obj = Cpanel::SafeRun::Object->new(
            program => "$Cpanel::ConfigFiles::CPANEL_ROOT/scripts/slurp_exim_mainlog",
            args    => [qw( --reimport )],
        );
    }
    return 1;
}

#TODO use AutoRebuildSchemaBase’s mechanism for schema updates.
sub _schema_check {
    my ( $self, $opts ) = @_;

    my $current_version = $self->_get_schema_version();
    my $schema_version  = $self->_SCHEMA_VERSION();

    if ( $current_version < $schema_version ) {

        my $upgrade_func_version = $schema_version;
        $upgrade_func_version =~ tr/\./_/;

        # This is a pretty naive check, please add a stepped version upgrade (or some other solution) if we need to upgrade through a few versions
        if ( my $upgrade_func = $self->can("_upgrade_to_version_$upgrade_func_version") ) {
            return $upgrade_func->( $self, %$opts, from_version => $current_version, to_version => $schema_version );
        }

        die "There is no upgrade path from '$current_version' to '$schema_version'!!";
    }

    return;
}

sub _upgrade_to_version_3_0 {
    my ($self) = @_;

    my $upgrade_sql = <<'SQL';
BEGIN EXCLUSIVE TRANSACTION;

CREATE TABLE IF NOT EXISTS failures_v3 (
  sendunixtime integer NOT NULL DEFAULT '0',
  msgid char(23) NOT NULL DEFAULT '',
  email char(255) NOT NULL DEFAULT '',
  deliveredto char(255) NOT NULL DEFAULT '',
  transport_method char(45) NOT NULL DEFAULT 'remote_smtp',
  "host" char(255) NOT NULL DEFAULT '',
  ip char(46) NOT NULL DEFAULT '',
  message char(240) NOT NULL DEFAULT '',
  router char(65) NOT NULL DEFAULT '',
  deliveryuser char(30) NOT NULL DEFAULT '',
  deliverydomain char(255) NOT NULL DEFAULT '',
  PRIMARY KEY (sendunixtime,msgid,email,deliveredto)
);

INSERT INTO failures_v3 SELECT * FROM failures;

DROP TABLE failures;

ALTER TABLE failures_v3 RENAME TO failures;

CREATE INDEX IF NOT EXISTS email_sendunixtime_index_failures ON failures (email,sendunixtime);
CREATE INDEX IF NOT EXISTS msgid_sendunixtime_index_failures ON failures (msgid,sendunixtime);
CREATE INDEX IF NOT EXISTS deliverydomain_sendunixtime_index_failures ON failures (deliverydomain,sendunixtime);
CREATE INDEX IF NOT EXISTS deliveryuser_sendunixtime_index_failures ON failures (deliveryuser,sendunixtime);
CREATE INDEX IF NOT EXISTS email_deliveryuser_sendunixtime_index_failures ON failures (email,deliveryuser,sendunixtime);


CREATE TABLE IF NOT EXISTS defers_v3 (
  sendunixtime integer NOT NULL DEFAULT '0',
  msgid char(23) NOT NULL DEFAULT '',
  email char(255) NOT NULL DEFAULT '',
  transport_method char(45) NOT NULL DEFAULT 'remote_smtp',
  "host" char(255) NOT NULL DEFAULT '',
  ip char(46) NOT NULL DEFAULT '',
  message char(240) NOT NULL DEFAULT '',
  router char(65) NOT NULL DEFAULT '',
  deliveryuser char(30) NOT NULL DEFAULT '',
  deliverydomain char(255) NOT NULL DEFAULT '',
  PRIMARY KEY (sendunixtime,msgid,email)
);

INSERT INTO defers_v3 SELECT * FROM defers;

DROP TABLE defers;

ALTER TABLE defers_v3 RENAME TO defers;

CREATE INDEX IF NOT EXISTS email_sendunixtime_index_defers on defers (email,sendunixtime);
CREATE INDEX IF NOT EXISTS msgid_sendunixtime_index_defers ON defers (msgid,sendunixtime);
CREATE INDEX IF NOT EXISTS deliverydomain_sendunixtime_index_defers ON defers (deliverydomain,sendunixtime);
CREATE INDEX IF NOT EXISTS deliveryuser_sendunixtime_index_defers ON defers (deliveryuser,sendunixtime);
CREATE INDEX IF NOT EXISTS email_deliveryuser_sendunixtime_index_defers ON defers (email,deliveryuser,sendunixtime);

CREATE TABLE IF NOT EXISTS sends_v3 (
  sendunixtime integer NOT NULL DEFAULT '0',
  msgid char(23) NOT NULL DEFAULT '',
  email char(255) NOT NULL DEFAULT '',
  processed integer NOT NULL DEFAULT '0',
  "user" char(30) NOT NULL DEFAULT '',
  size integer NOT NULL DEFAULT '0',
  ip char(46) NOT NULL DEFAULT '',
  auth char(30) NOT NULL DEFAULT '',
  "host" char(255) NOT NULL DEFAULT '',
  domain char(255) NOT NULL DEFAULT '',
  localsender integer NOT NULL DEFAULT '1',
  spamscore double NOT NULL DEFAULT 0,
  sender char(255) NOT NULL DEFAULT '',
  PRIMARY KEY (sendunixtime,msgid,email)
);

INSERT INTO sends_v3 SELECT * FROM sends;

DROP TABLE sends;

ALTER TABLE sends_v3 RENAME TO sends;

CREATE INDEX IF NOT EXISTS sendunixtime_domain_user_msgid_index_sends ON sends (sendunixtime,domain,"user",msgid);
CREATE INDEX IF NOT EXISTS user_sendunixtime_index_sends ON sends ("user",sendunixtime);
CREATE INDEX IF NOT EXISTS msgid_user_index_sends ON sends (msgid,"user");
CREATE INDEX IF NOT EXISTS msgid_sendunixtime_index_sends ON sends (msgid, sendunixtime);
CREATE INDEX IF NOT EXISTS domain_user_sendunixtime_index_sends ON sends (domain,"user",sendunixtime);
CREATE INDEX IF NOT EXISTS email_sendunixtime_user_index_sends ON sends (email,sendunixtime,"user");
CREATE INDEX IF NOT EXISTS sender_sendunixtime_user_index_sends ON sends (sender,sendunixtime,"user");
CREATE INDEX IF NOT EXISTS user_sendunixtime_spamscore_ip_index_sends ON sends ("user",sendunixtime,spamscore,ip);


CREATE TABLE IF NOT EXISTS smtp_v3 (
  sendunixtime integer NOT NULL DEFAULT '0',
  msgid char(23) NOT NULL DEFAULT '',
  email char(255) NOT NULL DEFAULT '',
  processed integer NOT NULL DEFAULT '0',
  transport_method char(45) NOT NULL DEFAULT 'remote_smtp',
  transport_is_remote integer NOT NULL DEFAULT '1',
  "host" char(255) NOT NULL DEFAULT '',
  ip char(46) NOT NULL DEFAULT '',
  deliveredto char(255) NOT NULL DEFAULT '',
  router char(65) NOT NULL DEFAULT '',
  deliveryuser char(30) NOT NULL DEFAULT '',
  deliverydomain char(255) NOT NULL DEFAULT '',
  countedtime integer NOT NULL DEFAULT '0',
  countedhour integer NOT NULL DEFAULT '0',
  counteddomain char(255) NOT NULL DEFAULT '',
  PRIMARY KEY (sendunixtime,msgid,email,deliveredto,router)
);

INSERT INTO smtp_v3 SELECT * FROM smtp;

DROP TABLE smtp;

ALTER TABLE smtp_v3 RENAME TO smtp;

CREATE INDEX IF NOT EXISTS msgid_index_smtp ON smtp (msgid);
CREATE INDEX IF NOT EXISTS msgid_sendunixtime_index_smtp ON smtp (msgid, sendunixtime);
CREATE INDEX IF NOT EXISTS deliverydomain_sendunixtime_index_smtp ON smtp (deliverydomain,sendunixtime);
CREATE INDEX IF NOT EXISTS deliveryuser_sendunixtime_index_smtp ON smtp (deliveryuser,sendunixtime);
CREATE INDEX IF NOT EXISTS email_sendunixtime_index_smtp ON smtp (email,sendunixtime);
CREATE INDEX IF NOT EXISTS email_deliveryuser_sendunixtime_index_smtp ON smtp (email,deliveryuser,sendunixtime);
CREATE INDEX IF NOT EXISTS processed_transport_is_remote_index_smtp ON smtp (processed,transport_is_remote);

INSERT OR REPLACE INTO metadata (key,value) VALUES ('schema_version', '3.0');

COMMIT;
SQL

    my $dbh = $self->_get_production_dbh();
    $dbh->do($upgrade_sql);

    return;
}

sub _upgrade_to_version_2_0 {
    my ($self) = @_;

    my $dbh = $self->_get_production_dbh();

    $dbh->do('BEGIN EXCLUSIVE TRANSACTION');
    $dbh->do("ALTER TABLE sends ADD sender char(255) DEFAULT '' NOT NULL");
    $dbh->do('CREATE INDEX IF NOT EXISTS sender_sendunixtime_user_index_sends ON sends (sender,sendunixtime,"user")');
    $dbh->do("INSERT OR REPLACE INTO metadata (key,value) VALUES ('schema_version', '2.0')");
    $dbh->do('COMMIT');

    return;
}

sub _PATH {
    return $Cpanel::EximStats::Constants::EXIMSTATS_SQLITE_DB;
}

# PRAGMA quick_check may be too slow for this DB since it can grow so large.
# The schema check will have to be 'good enough' for now.
sub _quick_integrity_check {
    return 1;
}

sub _SCHEMA_NAME { return 'eximstats' }

sub _SCHEMA_VERSION {
    return '3.0';
}

1;
