package Cpanel::SQLite::AutoRebuildSchemaBase;

# cpanel - Cpanel/SQLite/AutoRebuildSchemaBase.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::SQLite::AutoRebuildBase );

use Cpanel::DBI::SQLite  ();
use Cpanel::Exception    ();
use Cpanel::LoadModule   ();
use Cpanel::SQLite::Busy ();

use DBD::SQLite ();

use Try::Tiny;

my $MAX_BROKEN_DBS = 3;

#overridden in tests
our $_BASE = '/usr/local/cpanel/etc/db';

sub _SCHEMA_PATH_BASE { return "$_BASE/sqlite_schemas" }

=encoding utf-8

=head1 NAME

Cpanel::SQLite::AutoRebuildSchemaBase

=head1 SYNOPSIS

    package My::Datastore;

    use constant {
        _PATH => '/path/to/datastore',

        # See below about schema initialization.
        _SCHEMA_NAME => 'my_datastore',

        # See below about automated schema upgrades.
        _SCHEMA_VERSION => 1,
    };

    package main;

    # Will rebuild the sqlite db if it has become corrupt
    #
    my $dbh = My::Datastore->dbconnect();

    # Will NOT rebuild the sqlite db
    $dbh = My::Datastore->dbconnect_no_rebuild();

=head1 DESCRIPTION

This module manages the creation of the database handles to the a sqlite database.
It also handles the creation and recreation of the database if it hasn't been created yet
or has become corrupt.

NOTE: We use SQLite as the backend now. Please do NOT use the same dbh after a fork. Get a new dbh.

=head1 FUNCTIONS

=head2 dbconnect()

This function gets a database handle to the SQLite database. If the database does not exist
or has become corrupted, this function will rebuild the database. In case some of the data from the old
database may be retrieved, the old database is moved out of the way and kept in the same directory.

=head3 Arguments

None.

=head3 Returns

A database handle to a SQLite database

=head3 Exceptions

None, exceptions are logged.

=cut

sub dbconnect {
    my ( $class, %opts ) = @_;

    return $class->_dbconnect( 1, \%opts );
}

=head2 dbconnect_no_rebuild()

This function gets a database handle to the database. Unlike C<dbconnect()>, this function
does not build or rebuild the database if it does not exist or cannot be opened.

=head3 Arguments

None.

=head3 Returns

A database handle to a SQLite database. On failure, an empty list is returned.

=head3 Exceptions

None, exceptions are logged.

=cut

sub dbconnect_no_rebuild {
    my ( $class, %opts ) = @_;

    return $class->_dbconnect( 0, \%opts );
}

sub _dbconnect {
    my ( $class, $allow_rebuild, $opts ) = @_;

    my $dbh;
    try {
        my $db = $allow_rebuild ? $class->new_with_wait(%$opts) : $class->new_without_rebuild(%$opts);
        $dbh = $db->_get_production_dbh($opts);
    }
    catch {
        my $eval_error = $_;
        require Cpanel::Logger;
        my $path = $class->_PATH($opts);
        Cpanel::Logger->new->warn("Cannot connect to database: $path: $DBI::errstr ($eval_error)");
    };

    return if !$dbh;

    return $dbh;
}

# TODO: This is not needed anymore since we switch
# to SQLite, it should be removed in a future version.
sub _execute_sql {
    my ( $class, %OPTS ) = @_;

    my $dbh = $OPTS{dbh};
    if ( !$dbh ) {
        die "Could not connect to sqlite: $DBI::errstr: $@ $!";
    }

    foreach my $line ( split( /;/, $OPTS{'sql'} ) ) {
        next            if ( $line =~ /^\s*$/i || $line =~ /^\s*CONNECT/i );
        print "$line\n" if $OPTS{'verbose'};
        $dbh->do($line);
    }
    return 1;
}

sub _get_production_dbh {
    my ( $self, $opts ) = @_;

    if ( $self->{_production_dbh} && $self->{_production_dbh}->ping ) {
        return $self->{_production_dbh};
    }

    my $dbh = Cpanel::DBI::SQLite->connect(
        {
            db                               => $self->_PATH($opts),
            sqlite_open_flags                => DBD::SQLite::OPEN_READWRITE(),
            sqlite_allow_multiple_statements => 1,
        }
    );

    $self->{_production_dbh} = $dbh;

    # for debug
    #$dbh->sqlite_trace( sub { print join( ' - ', @_ ) . "\n" } );

    $dbh->sqlite_busy_timeout( Cpanel::SQLite::Busy::TIMEOUT() );

    return $dbh;
}

sub _get_schema_version {
    my ( $self, $opts ) = @_;

    my $schema_version;

    try {
        my $dbh = $self->_get_production_dbh($opts);
        if ( !$self->{'_did_integrity_check'} && !$self->{'_did_quick_check'} ) {
            $self->_quick_integrity_check($opts);
        }
        ($schema_version) = @{ $dbh->selectcol_arrayref( 'SELECT value FROM metadata WHERE key = ?', undef, 'schema_version' ) };
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

        die Cpanel::Exception::create( 'Database::DatabaseCreationInProgress', [ database => $self->_PATH() ] );
    };

    #The initial AutoSSL cPStore queue SQLite shipped without
    #a schema_version entry in its metadata.
    return $schema_version || 0;
}

sub _schema_check {
    my ( $self, $opts ) = @_;

    # This doesn't have to be interesting until we need to update the schema
    my $version = $self->_get_schema_version($opts);
    for my $next ( ( 1 + $version ) .. $self->_SCHEMA_VERSION() ) {
        my $upgrade_module = ( ref $self ) . "::schema_v$next";
        Cpanel::LoadModule::load_perl_module($upgrade_module);

        my $dbh = $self->_get_production_dbh($opts);

        $dbh->do('SAVEPOINT __generic_schema_update');

        my $upgrader = $upgrade_module->can('upgrade') or do {
            die "$upgrade_module lacks the “upgrade” function!";
        };

        $upgrader->($dbh);

        $dbh->do(
            qq<
            REPLACE INTO metadata (key, value) VALUES ('schema_version', '$next');
            RELEASE SAVEPOINT __generic_schema_update;
        >
        );
    }

    return;
}

sub _schema_path {
    my ($self) = @_;

    return _SCHEMA_PATH_BASE() . '/' . $self->_SCHEMA_NAME();
}

sub _create_db {
    my ( $class, %OPTS ) = @_;

    require Cpanel::Umask;
    require Cpanel::LoadFile;

    # By default SQLite creates DBs with mode 0644 - we want 0600.
    my $umask = Cpanel::Umask->new(0077);
    my $dbh   = Cpanel::DBI::SQLite->connect(
        {
            db                               => $class->_PATH( \%OPTS ),
            sqlite_open_flags                => DBD::SQLite::OPEN_CREATE | DBD::SQLite::OPEN_READWRITE(),
            sqlite_allow_multiple_statements => 1,
        }
    );

    # for debug
    #$dbh->sqlite_trace( sub { print join( ' - ', @_ ) . "\n" } );

    #We want this for all SQLite DBs, and it needs to be set outside
    #the transaction or else it silently fails.
    $class->_execute_sql(
        dbh => $dbh,
        sql => 'pragma journal_mode = wal;',
    );

    $class->_setup_schema( $dbh, %OPTS );
    $class->_setup_metadata_version($dbh);

    if ( $class->can('_create_db_post') ) {
        $class->_create_db_post( %OPTS, dbh => $dbh );
    }

    return;
}

sub _setup_schema {
    my ( $class, $dbh, %OPTS ) = @_;
    $dbh->sqlite_busy_timeout( Cpanel::SQLite::Busy::TIMEOUT() );

    my $schema = Cpanel::LoadFile::load( $class->_schema_path() );

    $dbh->do('SAVEPOINT __schema_setup');

    $class->_setup_metadata($dbh);

    $class->_execute_sql( sql => $schema, dbh => $dbh, exists $OPTS{verbose} ? ( verbose => $OPTS{verbose} ) : () );

    $dbh->do('RELEASE SAVEPOINT __schema_setup');

    return 1;
}

sub _setup_metadata {
    my ( $class, $dbh ) = @_;
    return $dbh->do(
        qq<
        CREATE TABLE IF NOT EXISTS metadata (
            key text primary key,
            value text
        );
    >
    );
}

sub _setup_metadata_version {
    my ( $class, $dbh ) = @_;
    my $schema_version = $class->_SCHEMA_VERSION();

    return $dbh->do(
        qq<
        INSERT INTO metadata (key, value) VALUES ('schema_version', '$schema_version');
    >
    );
}

sub _handle_invalid_database {
    my ( $class, %OPTS ) = @_;

    my $db_path = $class->_PATH( \%OPTS );
    return if !-e $db_path;

    if ( -d _ ) {
        die "“$db_path” is a directory, not an SQLite file!";
    }

    require Cpanel::NameVariant;
    require Cpanel::Autodie;
    require Cpanel::Time::ISO;

    my $new_filename = Cpanel::NameVariant::find_name_variant(
        max_length => 254,
        name       => $db_path . '.broken.' . Cpanel::Time::ISO::unix2iso(),
        test       => sub { return !-e $_[0] },
    );

    Cpanel::Autodie::rename( $db_path, $new_filename );

    $class->_clean_old_broken_dbs( \%OPTS );

    return { had_old_db => 1 };
}

sub _clean_old_broken_dbs {
    my ( $class, $opts ) = @_;

    require Cpanel::FileUtils::Dir;
    require File::Basename;

    my $DB_DIR    = File::Basename::dirname( $class->_PATH($opts) );
    my $DB_REGEX  = File::Basename::basename( $class->_PATH($opts) );
    my $dir_nodes = Cpanel::FileUtils::Dir::get_directory_nodes($DB_DIR);
    my @old_dbs   = sort grep { /^\Q$DB_REGEX\E.broken/ } @$dir_nodes;

    if ( ( my $dbs_to_remove = ( scalar @old_dbs ) - $MAX_BROKEN_DBS ) > 0 ) {
        require Cpanel::Autodie;
        Cpanel::Autodie::unlink_if_exists( $DB_DIR . '/' . $_ ) for splice( @old_dbs, 0, $dbs_to_remove );
    }

    return;
}

=head1 HOW TO USE THIS CLASS

This is a base class; to use it, you need to create a subclass that supplies
a few constants/methods that give datastore-specific information:

=over

=item * C<_PATH()> - The path to the datastore

=item * C<_SCHEMA_VERSION()> - The current schema version, an integer.
See below about schema upgrades.

=item * C<_SCHEMA_NAME()> - The schema’s name (see below)

=back

You also need to define the database schema. To do this, just create
the schema file in F</usr/local/cpanel/etc/db/sqlite_schemas/$SCHEMA_NAME>,
where C<$SCHEMA_NAME> is the return of your subclass’s C<_SCHEMA_NAME()>
method.

B<NOTE:> This base class creates and handles the C<metadata> table
automatically. Please ignore that table in your code.

=head1 AUTOMATIC SCHEMA UPGRADES

This class can automatically upgrade your database from an old schema
to a new one. To facilitate this:

=over

=item * Increment your subclass’s C<_SCHEMA_VERSION> by 1.

=item * Create a module C<${SUBCLASS_MODULE}::schema_v$SCHEMA_VERSION>,
where C<$SUBCLASS_MODULE> is the subclass module’s name and
C<$SCHEMA_VERSION> is the B<new> schema version. That module should have
an C<upgrade(DBH)> method, where the input C<DBH> is the database handle.
You can do your schema update logic in that function.

=back

That’s it! Next time the datastore is initialized, this base class will
migrate the database to the new schema.

Note that schema upgrades always happen within an SQLite SAVEPOINT, so
you shouldn’t need to create a transaction in your upgrade logic.

Again, just ignore the C<metadata> table in your upgrade logic.

=cut

sub _PATH {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

sub _SCHEMA_NAME {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

sub _SCHEMA_VERSION {
    die Cpanel::Exception::create( 'AbstractClass', [__PACKAGE__] );
}

1;
