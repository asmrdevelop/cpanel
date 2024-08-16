package Whostmgr::Transfers::Session::DBBackend;

# cpanel - Whostmgr/Transfers/Session/DBBackend.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent 'Cpanel::Destruct::DestroyDetector';

use constant FORK_CHECKS => 0;

use Cpanel::Exception      ();
use Cpanel::DBI::SQLite    ();
use Cpanel::SQLite::Compat ();
use Cpanel::SQLite::Busy   ();
use Cpanel::Mkdir          ();

use Whostmgr::Transfers::Session::Config ();
use Whostmgr::ACLS                       ();

use DBD::SQLite  ();
use Umask::Local ();

#
# We track open sqlite dbs to ensure we never open up the database if
# it has already been opened or left open by a parent process to avoid
# corruption and failure.  See https://www.sqlite.org/howtocorrupt.html
#
# Database /var/tmp/27770.T_CPANEL_BACKUP_RESTOREQUEUE_T__.PS3o2RQf5AhmJl3U.tmp/whmxfer.sqlite
# Error: file is encrypted or is not a database.
#
# The above error is caused by having multiple database handles to the same database.
#
our %OPEN_DB_FILES;

my $locale;

our $SESSIONS_TABLE = 'sessions';

# TODO: Convert this module to use Cpanel::SQLite::AutoRebuildSchemaBase

our $SQLITE_BUSY_TIMEOUT = Cpanel::SQLite::Busy::TIMEOUT();    # same as we use for Cpanel::SQLite::AutoRebuildSchemaBase

my @session_schema = (
    { 'name' => 'sessionid',   'type' => 'char(255)',  'notnull' => 1, 'dflt_value' => undef,     'pk' => 1 },
    { 'name' => 'initiator',   'type' => 'char(255)',  'notnull' => 0, 'dflt_value' => 'unknown', 'pk' => 0 },
    { 'name' => 'creator',     'type' => 'char(255)',  'notnull' => 0, 'dflt_value' => 'root',    'pk' => 0 },
    { 'name' => 'pid',         'type' => 'bigint(20)', 'notnull' => 0, 'dflt_value' => 0,         'pk' => 0 },
    { 'name' => 'version',     'type' => 'double',     'notnull' => 0, 'dflt_value' => 0,         'pk' => 0 },
    { 'name' => 'target_host', 'type' => 'char(255)',  'notnull' => 0, 'dflt_value' => undef,     'pk' => 0 },
    { 'name' => 'source_host', 'type' => 'char(255)',  'notnull' => 0, 'dflt_value' => undef,     'pk' => 0 },
    { 'name' => 'state',       'type' => 'bigint(20)', 'notnull' => 0, 'dflt_value' => 0,         'pk' => 0 },
    { 'name' => 'starttime',   'type' => 'datetime',   'notnull' => 0, 'dflt_value' => undef,     'pk' => 0 },
    { 'name' => 'endtime',     'type' => 'datetime',   'notnull' => 0, 'dflt_value' => undef,     'pk' => 0 },
);

sub new {
    my ( $class, %OPTS ) = @_;

    my $self = bless {}, $class;

    if ( $OPTS{'master_dbh'} ) {
        if ( !ref $OPTS{'master_dbh'} || !eval { $OPTS{'master_dbh'}->isa('Cpanel::DBI::SQLite::db'); } ) {
            _confess('master_dbh must be a sqlite handle. It is a: $OPTS{master_dbh}');
        }
        $self->{'_master_dbh'} = $OPTS{'master_dbh'};

        # Do not set _creator_pid as we didn't create it
    }
    else {
        $self->_create_master_dbi_handle();
        $self->_setup_or_recreate_master_db();
    }

    if ( $OPTS{'id'} ) {
        $self->get_session_connection( $OPTS{'id'} );
    }

    # Cruft that we inherted from
    # Case 176937 - --force should override disk space checks
    $self->{'ignore_disk_space'} = exists $OPTS{'ignore_disk_space'} ? $OPTS{'ignore_disk_space'} : 0;

    return $self;
}

sub drop_session_db {
    my ( $self, $session_id ) = @_;

    if ( $self->{'session_id'} && $self->{'session_id'} eq $session_id ) {
        $self->disconnect_session_db();
    }

    $self->_unlink_sqlite_db( $self->_session_db_path($session_id) );

    return 1;
}

sub get_master_dbh {
    if ( !$_[0]->{'_master_dbh'} ) {
        if ( $_[0]->{'_master_dbh_disconnect_trace'} ) {
            _confess("master_dbh: Already disconnected in this process via: $_[0]->{'_master_dbh_disconnect_trace'}");
        }

        _confess("master_dbh: Never connected in this process");
    }
    return $_[0]->{'_master_dbh'};
}

sub _unlink_sqlite_db {
    my ( $self, $db_path ) = @_;
    return unlink( map { $db_path . $_ } ( '', '-wal', '-shm' ) );

}

sub _session_db_path {
    my ( $self, $session_id ) = @_;
    die if $session_id =~ tr{/}{};
    return $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $session_id . '/db.sqlite';
}

sub _get_session_creator {
    my ( $self, $session_id ) = @_;

    my $creator = $self->get_master_dbh()->selectrow_array( "select creator from sessions where sessionid=?;", {}, $session_id );
    return ( $creator || 'root' );
}

sub get_session_connection {
    my ( $self, $session_id ) = @_;

    if ( $self->{'session_id'} && $self->{'session_id'} eq $session_id && $self->{'_session_dbh'} ) {
        return $self->{'_session_dbh'};
    }

    # This is our access control to prevent
    # resellers from accessing sessions that they do not
    # own.  It's built in to the lowest level of the system
    # to ensure any refactoring at higher levels does not open
    # up a leak.
    #
    # If the $ENV{'REMOTE_USER'} is not set we assume that the call
    # is not being run though WHM and access will always be granted.
    # This is important because Whostmgr::ACLS assumes no access if
    # $ENV{'REMOTE_USER'}  is unset and we call this code outside of WHM
    #
    # Special case: Do not call Whostmgr::ACLS::init_acls();
    # here because we only want hasroot() to be effective if
    # we are running under WHM or xml-api.
    # This ensures that if the caller does not unexpectedly grant access
    # to a session by forgetting to clear the REMOTE_USER variable.
    # We expect that the caller runing Whostmgr::ACLS::init_acls() will
    # have trust in $ENV{'REMOTE_USER'}. See Whostmgr/ACLS.pm for more
    # info.
    #
    unless ( !length $ENV{'REMOTE_USER'} || Whostmgr::ACLS::hasroot() || $self->_get_session_creator($session_id) eq $ENV{'REMOTE_USER'} ) {
        die Cpanel::Exception->create_raw( 'Access Denied to the session: ' . $session_id );
    }

    my $path = $self->_session_db_path($session_id);
    if ( $OPEN_DB_FILES{$path} ) {
        _confess("session_dbh: $session_id: Already connected in this process");
    }

    my $dbh;
    {
        my $umask_local = Umask::Local->new(0077);
        $dbh = Cpanel::DBI::SQLite->connect(
            {
                db                => $path,
                sqlite_open_flags => DBD::SQLite::OPEN_READWRITE() | DBD::SQLite::OPEN_CREATE(),
            }
        );
    }
    if ($dbh) {
        $dbh->do('PRAGMA encoding = "UTF-8";');
        Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed($dbh);
        $dbh->sqlite_busy_timeout( $SQLITE_BUSY_TIMEOUT + int rand(5000) );
        $self->{'session_id'}           = $session_id;
        $self->{'_session_creator_pid'} = $$;
        $OPEN_DB_FILES{$path}           = 1;
        return ( $self->{'_session_dbh'} = $dbh );
    }

    die Cpanel::Exception::create( 'Database::Error', "Unable to connect to [asis,SQLite]: unknown error." );
}

sub _create_master_dbi_handle {
    my ($self) = @_;

    my $path = $self->_get_master_db_path();
    if ( $OPEN_DB_FILES{$path} ) {
        _confess("master_dbh: Already connected in this process");
    }

    Cpanel::Mkdir::ensure_directory_existence_and_mode( $Whostmgr::Transfers::Session::Config::SESSION_DIR, 0700 );

    {
        my $umask_local = Umask::Local->new(0077);
        $self->{'_master_dbh'} = Cpanel::DBI::SQLite->connect(
            {
                db                => $path,
                sqlite_open_flags => DBD::SQLite::OPEN_READWRITE() | DBD::SQLite::OPEN_CREATE(),
            }
        );
    }

    if ( !$self->{'_master_dbh'} ) {
        die Cpanel::Exception::create( 'Database::Error', "Unable to connect to [asis,SQLite]: unknown error." );
    }

    $self->{'_master_dbh'}->sqlite_busy_timeout( $SQLITE_BUSY_TIMEOUT + int rand(5000) );

    $OPEN_DB_FILES{$path} = 1;
    $self->{'_creator_pid'} = $$;

    return 1;
}

sub _get_master_db_path {
    my ($self) = @_;

    return $Whostmgr::Transfers::Session::Config::SESSION_DIR . '/' . $Whostmgr::Transfers::Session::Config::DBNAME . '.sqlite';
}

sub _setup_or_recreate_master_db {
    my ($self) = @_;

    my $err;
    my $current_session_schema;
    {
        local $@;

        # If the database doesn't exist this will provide a warning. We expect that, so why emit it?
        local $self->{'_master_dbh'}->{'PrintError'} = 0;
        eval { $current_session_schema = $self->{'_master_dbh'}->selectall_arrayref("PRAGMA table_info('sessions');"); };

        if ($@) {
            $err = $@;
        }
        elsif ( !$current_session_schema || !@$current_session_schema ) {
            $err = 'Empty schema';
        }
    }

    if ( !$err ) {
        local $@;
        eval { $self->_ensure_schema_has_all_required_columns($current_session_schema); };
        if ($@) {
            warn;
            $err = $@;
        }
    }

    if ($err) {
        $self->disconnect();
        $self->_unlink_sqlite_db( $self->_get_master_db_path() );
        $self->_create_master_dbi_handle();
        $self->_create_master_db_schema();
    }

    $self->{'_master_dbh'}->do('PRAGMA encoding = "UTF-8";');
    Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed( $self->{'_master_dbh'} );

    return 1;
}

# NOTE: This does not do alters to change types
# It will only add missing columns
sub _ensure_schema_has_all_required_columns {
    my ( $self, $current_session_schema ) = @_;

    my %current_columns = map { $_->[1] => 1 } @{$current_session_schema};
    foreach my $column (@session_schema) {
        if ( !$current_columns{ $column->{'name'} } ) {
            $self->{'_master_dbh'}->do( 'ALTER table sessions ADD COLUMN ' . $self->_generate_column_from_schema_hash($column) );
        }
    }

    return 1;
}

sub disconnect {
    my ($self) = @_;

    if ( exists $self->{'_master_dbh'} ) {
        my $path = $self->_get_master_db_path();
        delete $OPEN_DB_FILES{$path};
    }
    if ( $self->{'_master_dbh'} ) {
        eval { $self->{'_master_dbh'}->disconnect(); } or warn $self->{'_master_dbh'}->errstr() . ": $@: $!";
        delete $self->{'_master_dbh'};
        require Carp;
        $self->{'_master_dbh_disconnect_trace'} = Carp::shortmess();
    }
    $self->disconnect_session_db();
    return 1;
}

sub disconnect_session_db {
    my ($self) = @_;

    if ( exists $self->{'_session_dbh'} ) {
        if ( $self->{'session_id'} ) {
            my $path = $self->_session_db_path( $self->{'session_id'} );
            delete $OPEN_DB_FILES{$path};
        }
    }
    if ( $self->{'_session_dbh'} ) {
        eval { $self->{'_session_dbh'}->disconnect(); } or warn $self->{'_session_dbh'}->errstr() . ": $@: $!";
        if ( $self->{'_session_creator_pid'} && $self->{'_session_creator_pid'} == $$ ) {
            $self->{'_session_creator_pid'} = undef;
        }
        delete $self->{'_session_dbh'};
    }
    return 1;
}

# to be used after fork()
sub reconnect {
    my ($self) = @_;
    $self->disconnect();
    $self->_create_master_dbi_handle();
    $self->get_session_connection( $self->{'session_id'} ) if $self->{'session_id'};
    return 1;
}

sub quote {
    my $self    = shift;
    my $args_ar = \@_;
    return $self->get_master_dbh()->quote(@$args_ar);
}

sub quote_identifier {
    my $self    = shift;
    my $args_ar = \@_;
    return $self->get_master_dbh()->quote_identifier(@$args_ar);
}

*table_exists = \&table_exists_in_session_db;    # provided for compat

sub table_exists_in_session_db {
    my ( $self, $table ) = @_;
    my $row = $self->session_sql( 'selectcol_arrayref', [ "select name from sqlite_master where type='table' and name=? /*table_exists*/;", {}, $table ] );
    return ( $row && $row->[0] ) ? 1 : 0;
}

sub table_exists_in_master_db {
    my ( $self, $table ) = @_;
    my $row = $self->master_sql( 'selectcol_arrayref', [ "select name from sqlite_master where type='table' and name=? /*table_exists*/;", {}, $table ] );
    return ( $row && $row->[0] ) ? 1 : 0;
}

#$sql can either be:
#   a single command, or
#   an arrayref of args to "do"
sub master_do {

    return $_[0]->master_sql( 'do', $_[1] );
}

#$sql can either be:
#   a single command, or
#   an arrayref of args to $method
sub master_sql {
    my ( $self, $method, $arg_ref ) = @_;
    if (FORK_CHECKS) {
        if ( $self->{'_master_dbh'}->original_pid() != $$ ) {
            _confess("master_sql: Attempted to access database in fork() child");
        }
    }
    return $self->get_master_dbh()->$method( ref $arg_ref ? @{$arg_ref} : ($arg_ref) );
}

#$sql can either be:
#   a single command, or
#   an arrayref of args to "do"
sub session_do {

    return $_[0]->session_sql( 'do', $_[1] );
}

#$sql can either be:
#   a single command, or
#   an arrayref of args to $method
sub session_sql {
    my ( $self, $method, $arg_ref ) = @_;

    if (FORK_CHECKS) {
        if ( $self->{'_session_dbh'}->original_pid() != $$ ) {
            _confess("session_sql: Attempted to access database in fork() child");
        }
    }
    my $dbh = $self->{'_session_dbh'} || _confess("session_sql: Missing session dbh");
    return $dbh->$method( ref $arg_ref ? @{$arg_ref} : ($arg_ref) );
}

sub _create_master_db_schema {
    my ($self) = @_;

    # TODO in v2 when we need to change the schema
    # Modularize Cpanel::BandwidthDB::Upgrade::upgrade_schema()
    # and use that
    local $@;

    eval {
        $self->{'_master_dbh'}->do(q<DROP TABLE IF EXISTS `sessions`;>);
        $self->{'_master_dbh'}->do( $self->_generate_create_sessions_statement() );
    };

    die Cpanel::Exception::create( 'Database::TableCreationFailed', [ table => $SESSIONS_TABLE, database => $Whostmgr::Transfers::Session::Config::DBNAME, error => $@ ] ) if $@;

    return 1;
}

sub _generate_create_sessions_statement {
    my ($self) = @_;
    my ( @columns, $primary_key );
    foreach my $column (@session_schema) {
        push @columns, $self->_generate_column_from_schema_hash($column);
        if ( $column->{'pk'} ) {
            $primary_key = "PRIMARY KEY (" . $self->{'_master_dbh'}->quote_identifier( $column->{'name'} ) . ")";
        }
    }
    push @columns, $primary_key if length $primary_key;
    return 'CREATE TABLE `sessions` (' . join( ",\n", @columns ) . ');';
}

sub _generate_column_from_schema_hash {
    my ( $self, $column ) = @_;
    return $self->{'_master_dbh'}->quote_identifier( $column->{'name'} ) .    #
      " $column->{'type'} " .                                                 #
      ( $column->{'notnull'} ? ' NOT NULL ' : ( exists $column->{'dflt_value'} ? " DEFAULT " . $self->_format_default_value( $column->{'dflt_value'} ) : '' ) );
}

sub _format_default_value {
    my ( $self, $value ) = @_;

    if ( length $value ) {
        return $self->{'_master_dbh'}->quote($value);
    }

    return 'NULL';
}

sub connected {
    my ($self) = @_;
    return ( $self->{'_session_dbh'} || $self->{'_master_dbh'} ) ? 1 : 0;
}

sub DESTROY {
    my ($self) = @_;

    $self->SUPER::DESTROY();

    if ( $self->{'_creator_pid'} && $self->{'_creator_pid'} == $$ ) {
        $self->disconnect();
    }

    # We may have not created the original db connection
    # but we may have created the session db connection
    elsif ( $self->{'_session_creator_pid'} && $self->{'_session_creator_pid'} == $$ ) {
        $self->disconnect_session_db();
    }

    return 1;
}

sub _confess {
    require Cpanel::Carp;
    die Cpanel::Carp::safe_longmess(@_);
}
1;
