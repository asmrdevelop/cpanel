package Cpanel::Backup::StreamFileList;

# cpanel - Cpanel/Backup/StreamFileList.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use File::Spec        ();

=head1 NAME

Cpanel::Backup::StreamFileList

=head1 SYNOPSIS

use Cpanel::Backup::StreamFileList;

@backup_dirs = Cpanel::Backup::StreamFileList::categorize_backups ( $backup_dir, $backup_path, $user );

=head1 DESCRIPTION

Provides useful routines to evaluate backups.

Note: all of this is based on knowing a user in the backup system.

=head1 SUBROUTINES

=cut

=head2 categorize_backup

Given a backup path, determine if it is compressed, uncompressed
or incremental.

=over 3

=item C<< $backup_path >>

The path to an actual backup.  E.g. /backup/2017-07-02

=item C<< $user >>

A known user, you must provide a username so that the function can evaluate accurately the type of backup.

=back

B<Returns>: Returns a hash ref of the backup

    { 'path' => '/backup/2017-01-01', 'type' => 0 },

=cut

sub categorize_backup {
    my ( $backup_dir, $path, $user ) = @_;

    if ( !$backup_dir || !$path || index( $path, $backup_dir ) != 0 ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The given backup path contains invalid data.' );
    }
    die Cpanel::Exception::create( 'InvalidParameter', 'No user name supplied.' ) if !$user;

    # Collapse duplicate '/' chars
    $backup_dir =~ tr{/}{}s;

    # Remove trailing slash.
    $backup_dir =~ s{/+$}{};

    my $backup_path = File::Spec->canonpath($path);

    my $backup_id = "ERROR";
    my $subdir    = substr( $backup_path, length($backup_dir) );
    if ( $subdir =~ m/^\/\d{4}-\d{2}-\d{2}$/ ) {
        $backup_id = substr( $subdir, 1 );
    }
    elsif ( $subdir =~ m/^\/weekly\/\d{4}-\d{2}-\d{2}$/ ) {
        $backup_id = substr( $subdir, 1 );
    }
    elsif ( $subdir =~ m/^\/monthly\/\d{4}-\d{2}-\d{2}$/ ) {
        $backup_id = substr( $subdir, 1 );
    }
    elsif ( $subdir =~ m/^\/weekly\/incremental\/?$/ ) {
        $backup_id = substr( $subdir, 1 );
    }
    elsif ( $subdir =~ m/^\/monthly\/incremental\/?$/ ) {
        $backup_id = substr( $subdir, 1 );
    }
    elsif ( $subdir =~ m/^\/incremental\/?$/ ) {
        $backup_id = substr( $subdir, 1 );
    }

    my $backup_dir_ref = {
        'path'     => $backup_path,
        'backupID' => $backup_id,
    };

    if ( -f $backup_path . "/accounts/${user}.tar" ) {
        $backup_dir_ref->{'type'}             = 0;                                        # uncompressed
        $backup_dir_ref->{'user_backup_path'} = $backup_path . "/accounts/${user}.tar";
    }
    elsif ( -f $backup_path . "/accounts/${user}.tar.gz" ) {
        $backup_dir_ref->{'type'}             = 1;                                           # compressed
        $backup_dir_ref->{'user_backup_path'} = $backup_path . "/accounts/${user}.tar.gz";
    }
    elsif ( -d $backup_path . "/accounts/${user}/" && -f $backup_path . "/accounts/${user}/backup_meta_data" ) {
        $backup_dir_ref->{'type'}             = 2;                                           # incremental
        $backup_dir_ref->{'user_backup_path'} = $backup_path . "/accounts/${user}";
    }
    else {
        $backup_dir_ref->{'type'} = 3;                                                       # unknown
    }

    return $backup_dir_ref;
}

=head2 get_backup_path_from_backup_id

Returns SCALAR of the backup path if it exists and is a directory or undef if not.

=over 3

=item C<< $backup_dir >>

The base backup dir, usuallly /backup but is configurable.

=item C<< $backup_id >>

The ID for a backup.

=back

=cut

sub get_backup_path_from_backup_id {
    my ( $backup_dir, $backup_id ) = @_;

    my $backup_path = File::Spec->canonpath( $backup_dir . '/' . $backup_id );
    return $backup_path if -d $backup_path;
    return;
}

=head2 categorize_backups

Get a list of refs for each backup in the system.  Categorizing it into one
of the three types of backups, uncompressed, compressed and incremental.

=over 3

=item C<< $backup_dir >>

The base backup dir, usuallly /backup but is configurable.

=item C<< $user >>

A known user, you must provide a username so that the function can evaluate accurately the type of backup.

=back

B<Returns>: Returns an array of refs similar to the following:

    [
        { 'path' => '/backup/2017-01-01', 'type' => 0 },
        { 'path' => '/backup/2017-01-02', 'type' => 1 },
        { 'path' => '/backup/2017-01-03', 'type' => 2 },
    ]

=cut

sub categorize_backups {
    my ( $backup_dir, $backup_path, $user ) = @_;

    if ( !$backup_dir ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The given backup path contains invalid data.' );
    }
    if ( !-d $backup_dir ) {    # Needs to be a directory or link to (hopefully) a directory
        die Cpanel::Exception::create( 'InvalidParameter', 'Invalid backup path. Enter a valid backup path.' );
    }
    $backup_path = File::Spec->canonpath($backup_path);

    my @backup_paths;
    my $fd;

    opendir $fd, $backup_path or die Cpanel::Exception::create( 'IO::FileOpenError', 'The system could not open the “[_1]” backup. Select another backup to restore.', [$backup_path] );

    while ( my $line = readdir($fd) ) {
        next if ( $line eq '.' || $line eq '..' );

        my $path = $backup_path . "/" . $line;

        next if ( !-d $path );

        # check out monthly or weekly

        if ( $line eq "monthly" || $line eq "weekly" ) {

            # XXX what's to prevent deep tail recursion on something like /backup/$date/monthly/monthly/monthly/monthly... ?
            push( @backup_paths, categorize_backups( $backup_dir, $path, $user ) );
            next;
        }

        my $backup_path_ref = categorize_backup( $backup_dir, $path, $user );
        push( @backup_paths, $backup_path_ref ) if ($backup_path_ref);
    }

    closedir($fd);

    return @backup_paths;
}

1;
