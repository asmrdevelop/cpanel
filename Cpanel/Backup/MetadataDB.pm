package Cpanel::Backup::MetadataDB;

# cpanel - Cpanel/Backup/MetadataDB.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                ();
use Cpanel::Backup::MetadataDB::Tiny ();

use parent qw( Cpanel::SQLite::AutoRebuildSchemaBase );

use constant {
    _SCHEMA_NAME => 'backup_metadata',

    _SCHEMA_VERSION => '3.1',
};

=head1 NAME

Cpanel::Backup::MetadataDB

=head1 DESCRIPTION

Subclass of Cpanel::Sqlite::AutoRebuildSchemaBase used for interacting with Backup Metadata DBs used by the file level restore feature of cPanel & WHM.

=head1 SYNOPSIS

    my $user = 'billy';
    my $dbh = Cpanel::Backup::MetadataDB->dbconnect( user => $user ) or die "Couldn't connect to database!";
    $dbh->do(...);

=head1 NOTES

The parent's _quick_integrity_check is disabled (always returns 1) for the sake of expediency.

=head1 METHODS

=head2 get_current_metadata_version

Returns the current version of the metadata schema.

=cut

sub get_current_metadata_version {
    return _SCHEMA_VERSION;
}

=head2 base_path

Returns the path to the directory containing metadata DBs.

Example:

    my $dbfile = base_path()."$username.db"

=cut

sub base_path {
    return Cpanel::Backup::MetadataDB::Tiny::base_path();
}

sub _PATH {
    my ( $class, $opts ) = @_;

    die Cpanel::Exception->create_raw("Need user!") if !length $opts->{user};
    my $path = $class->base_path() . '/' . $opts->{user} . '.db';

    die Cpanel::Exception::create( 'Database::DatabaseMissing', 'This feature is disabled until the next system backup runs.', [ $path, $opts->{user} ] ) if $opts->{check_exists} && !-f $path;

    return $path;
}

sub _quick_integrity_check {
    return 1;
}

# Remove this method when we're ready to do schema updates automagically
sub _get_schema_version {
    return _SCHEMA_VERSION();
}

1
