package Cpanel::Backup::Transport::DB;

# cpanel - Cpanel/Backup/Transport/DB.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Backup::Config ();
use Cpanel::Exception      ();
use Cpanel::Mkdir          ();
use Cpanel::Context        ();

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

use constant {
    _SCHEMA_NAME => 'backup_transport_history',

    _SCHEMA_VERSION => '0.1',
};

=head1 NAME

Cpanel::Backup::Transport::DB

=head1 DESCRIPTION

Subclass of Cpanel::Sqlite::AutoRebuildSchemaBase used for interacting with Backup Transport DBs used to keep track of what has been transported to remote systems.

=head1 SYNOPSIS

    my $user = 'billy';
    my $dbh = Cpanel::Backup::Transport::DB->dbconnect() or die "Couldn't connect to database!";
    $dbh->do(...);

=head1 SCHEMA

    TABLE 'occurrences'     (id,date)
    TABLE 'transports'      (id,transport)
    TABLE 'users'           (id,user)
    TABLE 'transport_history' (transport_id,user_id,occurrence_id)
        FKEY transport_id  -> transports.id
        FKEY user_id       -> user.id
        FKEY occurrence_id -> occurrences.id
    VIEW transport_import (mashes together occurrences, transports and users)
    VIEW happenings (transport_history to source table mapping)

=head1 METHODS

=head2 dbconnect

We override dbconnect() to automatically re-apply the schema so that we can deal with blank or corrupt databases gracefully.

This is not appropriate to apply with carte blanche in the parent class, given there is no guarantee that they properly create their data structures only IF NOT EXISTS.

=cut

# Override the constructor so that we blithely apply the schema, since it DOES have the protection of CREATE IF NOT EXISTS.
sub dbconnect {
    my ($self) = @_;
    my $dbh = $self->SUPER::dbconnect();
    $self->_setup_schema($dbh);
    return $dbh;
}

=head2 get_current_version

Returns the current version of the Transport Historyschema.

=cut

sub get_current_version {
    return _SCHEMA_VERSION;
}

# Remove this method when we're ready to do schema updates automagically
sub _get_schema_version {
    return _SCHEMA_VERSION();
}

sub _PATH {
    my ( $class, $opts ) = @_;

    my $conf       = Cpanel::Backup::Config::load();
    my $backup_dir = $conf->{'BACKUPDIR'} || '/backup/';
    if ( !-e $backup_dir ) {
        Cpanel::Mkdir::ensure_directory_existence_and_mode( $backup_dir, 0711 );
    }

    my $path = "$backup_dir/transports.db";

    die Cpanel::Exception::create( 'Database::DatabaseMissing', 'This feature is disabled until the next system backup runs.', [$path] ) if $opts->{check_exists} && !-f $path;

    return $path;
}

=head2 remove

Delete the backup transports database. Returns a boolean indicating whether the deletion succeeded. (Already missing is considered a success)

You must call this function in list context.

=cut

sub remove {
    my ($class) = @_;
    Cpanel::Context::must_be_list();
    my $db = $class->_PATH;
    unlink($db);
    return !-e $db, $db;
}

1;
