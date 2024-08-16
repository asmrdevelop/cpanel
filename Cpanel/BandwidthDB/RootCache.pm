package Cpanel::BandwidthDB::RootCache;

# cpanel - Cpanel/BandwidthDB/RootCache.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module is here to be the most minimal caching tool necessary to fulfill
# the root UI’s and APIs’ current needs; hence, it only does, for a given month:
#   - domain data
#   - total
#
# This is mostly here for WHM’s bandwidth usage UI, which harvests data for
# EVERY SINGLE DOMAIN ON THE SERVER and shovels it out to the UI. Previously
# we got this from individual files for each user; this way we only have to
# load one file rather than potentially thousands.
#
# An important part of this module’s design is that it does NOT add new data
# to what it already has; rather, it replaces. So, you can keep importing
# bandwidth data over and over, and nothing will be corrupted.
#----------------------------------------------------------------------

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use parent qw( Cpanel::SQLite::AutoRebuildBase );

use DBD::SQLite ();
use Try::Tiny;

use Cpanel::BandwidthDB::Constants ();
use Cpanel::DBI::SQLite            ();
use Cpanel::Exception              ();
use Cpanel::LoadModule             ();
use Cpanel::SQLite::Busy           ();

#exposed for testing
our $_path;
*_path = \$Cpanel::BandwidthDB::Constants::ROOT_CACHE_PATH;

#exposed for testing; empty this out to suppress the import
our $_IMPORT_MODULE = 'Cpanel::BandwidthDB::RootCache::Import';

#For potential future use.
my $SCHEMA_VERSION = 1;

#----------------------------------------------------------------------
#Static method
sub delete {
    require Cpanel::Autodie;
    Cpanel::Autodie::unlink_if_exists($_path);

    return;
}

#For subclasses
sub _PATH { return $_path }

sub _import_data_on_db_init {
    my ( $self, $new_sqlite, %opts ) = @_;

    #There are tests that empty out this variable to suppress the import;
    #otherwise, this will always be true.
    if ($_IMPORT_MODULE) {
        local $self->{'_dbh'} = $new_sqlite->dbh();

        Cpanel::LoadModule::load_perl_module($_IMPORT_MODULE);
        $_IMPORT_MODULE->can('import_from_bandwidthdbs')->(
            $self,
            $opts{'import_options'} ? %{ $opts{'import_options'} } : (),
        );
    }

    return 1;
}

sub _handle_invalid_database {
    my ($class) = @_;    # note $class not $self, this isn't an object

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');

    #If we got here, then we should unlink() and recreate the file.
    Cpanel::Autodie::unlink_if_exists( $class->_PATH() );

    return;
}

sub _create_db {
    my ( $class, %opts ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::RaceSafe::SQLite');

    #This module is here to prevent the case where the DB file
    #is there but the EXCLUSIVE TRANSACTION has yet to be opened.
    #It’s a small window, but hey.
    my $new_sqlite = Cpanel::FileUtils::RaceSafe::SQLite->new(
        path => $class->_PATH(),
    );

    my $dbh = $new_sqlite->dbh();

    my $self = bless { _dbh => $dbh }, $class;

    #Speed up creation since this is just a cache
    #and we will just try again if creating it fails.
    $dbh->do("PRAGMA journal_mode = OFF;");
    $dbh->do("PRAGMA synchronous = OFF;");

    #This places an advisory fcntl()-based lock on the DB file.
    #Anything else that tries to open an SQLite connection to the file
    #will get a failure.
    $dbh->do('BEGIN EXCLUSIVE TRANSACTION');

    #This is a bit unusual: we install without having done
    #anything other than lock the file. This, though, will
    #guarantee that nothing else will try to build this cache
    #at the same time as the current process .. which is important
    #on heavily loaded servers.
    #
    my $installed_our_file = $new_sqlite->install_unless_exists();

    if ( !$installed_our_file ) {
        $dbh->rollback();
        die Cpanel::Exception::create( 'Database::DatabaseCreationInProgress', [ database => $class->_PATH() ] );
    }

    _set_up_schema( $new_sqlite->dbh() );

    $self->_import_data_on_db_init( $new_sqlite, %opts );

    #Okay, now let’s put it all into use. This releases the fcntl() lock
    #and makes the file ready for production use.
    $dbh->do('COMMIT');

    return;
}

#STATIC
sub _set_up_schema {
    my ($dbh) = @_;

    $dbh->do(
        q<
        CREATE TABLE domains (
            name string,
            id integer primary key
        )
    >
    );

    $dbh->do(
        q<
        CREATE UNIQUE INDEX
            domains_name_index
        ON
            domains (name)
    >
    );

    $dbh->do(
        q<
        CREATE TABLE users (
            name string,
            id integer primary key
        )
    >
    );

    $dbh->do(
        q<
        CREATE TABLE monthly_domain_data (
            year        integer,
            month_num   integer,
            user_id     integer,
            domain_id   integer,
            bytes       integer,
            primary key (year, month_num, user_id, domain_id)
        )
    >
    );

    $dbh->do(
        q<
        CREATE INDEX
            domain_year_month_index
        ON
            monthly_domain_data ( year, month_num )
    >
    );

    $dbh->do(
        q<
        CREATE VIEW
            monthly_user_data
        AS SELECT
            year,
            month_num,
            user_id,
            SUM(monthly_domain_data.bytes) AS bytes
        FROM
            monthly_domain_data
        GROUP BY
            year, month_num, user_id
    >
    );

    $dbh->do(
        q<
        CREATE TABLE
            metadata (
                key string primary key,
                value string
            )
    >
    );

    #This will tell the constructor that the schema is complete;
    #thus, it MUST be the last thing to be done here!
    #XXX TODO: put in an explicit flag to that effect.
    $dbh->do( 'REPLACE INTO metadata (key, value) VALUES (?,?)', undef, 'schema_version', $SCHEMA_VERSION );

    return;
}

sub _get_schema_version {
    my ($self) = @_;

    my $schema_version;

    try {
        ($schema_version) = @{ $self->{'_dbh'}->selectcol_arrayref( 'SELECT value FROM metadata WHERE key = ?', undef, 'schema_version' ) };
    }
    catch {
        local $@ = $_;

        die if !try { $_->isa('Cpanel::Exception::Database::Error') };

        #SQLITE_BUSY here means that the file is locked exclusively,
        #which is what happens when doing the initial DB setup.
        #We just need to keep waiting.
        #
        #NOTE: DBD::SQLite will actually query the DB over and over when it
        #first receives SQLITE_BUSY, up until it reaches the timeout
        #given/set by sqlite_busy_timeout().
        #
        #Of course, if we got anything *other* than SQLITE_BUSY, then we
        #should rethrow that.
        #
        die if !$_->failure_is('SQLITE_BUSY');

        die Cpanel::Exception::create( 'Database::DatabaseCreationInProgress', [ database => $_path ] );
    };

    return $schema_version;
}

sub _get_production_dbh {
    my ($self) = @_;

    # Case CPANEL-99, ensure proper permissions for existing systems
    if ( -e $_path ) {
        chmod $Cpanel::BandwidthDB::Constants::ROOT_CACHE_FILE_PERMS, $_path;
    }

    my $dbh = Cpanel::DBI::SQLite->connect(
        {
            db                => $_path,
            sqlite_open_flags => DBD::SQLite::OPEN_READWRITE(),
        }
    );

    $dbh->sqlite_busy_timeout( Cpanel::SQLite::Busy::TIMEOUT() );

    $self->{_dbh} = $dbh;

    return $dbh;
}

sub _get_or_create_id_from_table_for_name {
    my ( $self, $table, $name ) = @_;

    my $id = $self->_query_id_from_table_for_name( $table, $name );
    return $id if defined $id;

    $self->_add_name_to_table( $name, $table );

    return $self->_query_id_from_table_for_name( $table, $name );
}

sub _add_name_to_table {
    my ( $self, $name, $table ) = @_;

    $self->{'_dbh'}->do( "INSERT INTO $table (name, id) VALUES (?,?)", undef, $name, undef );

    return;
}

sub _query_ids_from_table_for_names {
    my ( $self, $table, $names_ar ) = @_;

    my $dbh = $self->{'_dbh'};

    return @{ $dbh->selectcol_arrayref( "SELECT id FROM $table WHERE name IN (" . join( ',', map { $dbh->quote($_) } @$names_ar ) . ')' ) };
}

sub _query_id_from_table_for_name {
    my ( $self, $table, $name ) = @_;

    return ( $self->{'_dbh'}->selectrow_array( "SELECT id FROM $table WHERE name = ?", undef, $name ) )[0];
}

sub get_or_create_id_for_user {
    my ( $self, $username ) = @_;

    return $self->_get_or_create_id_from_table_for_name( 'users', $username );
}

sub get_or_create_id_for_domain {
    my ( $self, $name ) = @_;

    return $self->_get_or_create_id_from_table_for_name( 'domains', $name );
}

#Returns 1 if it did anything; 0 if it didn’t.
#
sub purge_user {
    my ( $self, $user ) = @_;

    my $dbh = $self->{'_dbh'};

    local $dbh->{'AutoCommit'} = 0;

    my $userid = $self->_query_id_from_table_for_name( 'users', $user );
    return 0 if !$userid;

    $dbh->do( 'DELETE FROM users WHERE id = ?',                    undef, $userid );
    $dbh->do( 'DELETE FROM monthly_domain_data WHERE user_id = ?', undef, $userid );

    $dbh->commit();

    return 1;
}

#Returns 1 if it did anything; 0 if it didn’t.
#
sub rename_user {
    my ( $self, $oldname, $newname ) = @_;

    return 0 + $self->{'_dbh'}->do(
        q<
            UPDATE users
            SET name = ?
            WHERE name = ?
        >,
        undef,
        $newname,
        $oldname,
    );
}

# WARNING! The inputs changed for this in version 72 so we can
# avoid recalcating the domain_id and user_id in the loop that
# feeds this since it was very very slow
sub set_user_domain_year_month_bytes {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $self, $user_id, $domain_id, $year, $month_num, $bytes ) = @_;

    (
        $self->{'_set_user_domain_year_month_bytes_statement'} ||= $self->{'_dbh'}->prepare(
            q<
            REPLACE INTO monthly_domain_data
                ( year, month_num, user_id, domain_id, bytes )
            VALUES (?, ?, ?, ?, ?)
        >
        )
    )->execute(
        $year,
        $month_num,
        $user_id,
        $domain_id,
        $bytes,
    );

    return;
}

#Returns a hashref of:
#   {
#       username1 => bytes1,
#       username2 => bytes2,
#       ...
#   }
#
sub get_user_bytes_as_hash {
    my ( $self, %opts ) = @_;

    my $dbh = $self->{'_dbh'};

    my @wheres = (
        'monthly_user_data.user_id = users.id',

        $self->_get_wheres_from_opts_hr( \%opts ),
    );

    my $sql_where = join( ' AND ', @wheres );

    my $sth = $dbh->prepare(
        qq<
            SELECT
                users.name,
                bytes
            FROM
                monthly_user_data,
                users
            WHERE
                $sql_where
            ORDER BY
                users.name
        >,
    );

    $sth->execute();

    return $self->_fetch_results_as_hash($sth);
}

#Returns a hashref of:
#   {
#       username1 => {
#           domain1 => bytes1,
#           domain2 => bytes2,
#           ...
#       },
#       username2 => {
#           domain3 => bytes3,
#           ...
#       },
#       ...
#   }
#
#NOTE: It is possible for two usernames to list the same domain.
#
sub get_user_domain_bytes_as_hash {
    my ( $self, %opts ) = @_;

    my @wheres = (
        'monthly_domain_data.user_id = users.id',
        'monthly_domain_data.domain_id = domains.id',

        $self->_get_wheres_from_opts_hr( \%opts ),
    );

    my $sql_where = join( ' AND ', @wheres );

    my $sth = $self->{'_dbh'}->prepare(
        qq<
            SELECT
                users.name,
                domains.name,
                bytes
            FROM
                monthly_domain_data,
                users,
                domains
            WHERE
                $sql_where
            ORDER BY
                users.name,
                domains.name
        >,
    );

    $sth->execute();

    return $self->_fetch_results_as_hash($sth);
}

sub import_from_bandwidthdb {
    my ( $self, $bwdb ) = @_;

    #There is no need to do this in a transaction
    #since, if a new record conflicts with an older one,
    #we just replace the older one.

    my $username = $bwdb->get_attr('username');

    my $by_month_hr = $bwdb->get_bytes_totals_as_hash(
        grouping => [ 'year_month', 'domain' ],
    );

    my $username_id = $self->get_or_create_id_for_user($username);
    my %domain_id_cache;

    for my $yrmo ( keys %$by_month_hr ) {
        my ( $yr, $mo ) = split m<->, $yrmo;

        for my $domain ( keys %{ $by_month_hr->{$yrmo} } ) {
            $self->set_user_domain_year_month_bytes(
                $username_id,
                ( $domain_id_cache{$domain} ||= $self->get_or_create_id_for_domain($domain) ),
                $yr,    #
                $mo,    #
                $by_month_hr->{$yrmo}{$domain},
            );
        }
    }

    return;
}

#NOTE: Potentially reusable; see similar logic in
#Cpanel::BandwidthDB::Read.
#
sub _fetch_results_as_hash {
    my ( $self, $sth ) = @_;

    my %res;

    my @row;

    my $cols_count = $sth->{'NUM_OF_FIELDS'};

    if ( $cols_count == 3 ) {
        $res{ $row[0] }{ $row[1] } = $row[2] while @row = $sth->fetchrow_array();
    }
    elsif ( $cols_count == 2 ) {
        $res{ $row[0] } = $row[1] while @row = $sth->fetchrow_array();
    }
    else {
        die "$cols_count column(s)!";
    }

    return \%res;
}

sub _get_wheres_from_opts_hr {
    my ( $self, $opts_hr ) = @_;

    my $dbh = $self->{'_dbh'};

    my @wheres;

    if ( $opts_hr->{'year'} ) {
        push @wheres, 'year = ' . $dbh->quote( $opts_hr->{'year'} );
    }

    if ( $opts_hr->{'month'} ) {
        push @wheres, 'month_num = ' . $dbh->quote( $opts_hr->{'month'} );
    }

    if ( $opts_hr->{'users'} ) {
        push @wheres,
          "user_id in (" . join(
            ',',
            $self->_query_ids_from_table_for_names( 'users', $opts_hr->{'users'} ),
          ) . ')';
    }

    return @wheres;
}

# PRAGMA quick_check may be too slow for this DB since it can grow so large.
# The schema check will have to be 'good enough' for now.
sub _quick_integrity_check {
    return 1;
}

sub _schema_check {
    my ($self) = @_;
    return $self->_get_schema_version();
}

1;
