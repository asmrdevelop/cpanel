
# cpanel - Cpanel/Transport/Files/Local.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Transport::Files::Local;

use strict;
use warnings;
use File::Spec                  ();
use Cpanel::Transport::Response ();
use File::Copy                  ();
use File::Path                  ();
use Cpanel::Locale              ();
use Cpanel::Backup::Config      ();
use Cpanel::BackupMount         ();
use Cpanel::LoadModule          ();

use parent 'Cpanel::Transport::Files';
my $locale;

my $DIR_PERM  = 0711;
my $FILE_PERM = 0600;

sub new {
    my ( $class, $OPTS, $CFG ) = @_;
    $locale ||= Cpanel::Locale->get_handle();

    _check_params($OPTS);

    my $self = bless $OPTS, $class;
    $self->{'config'} = $CFG;

    return $self;
}

sub _missing_parameters {
    my ($param_hashref) = @_;

    my @result = ();
    foreach my $key (qw/path/) {
        if ( !defined $param_hashref->{$key} ) {
            push @result, $key;
        }
    }

    my %defaults = (
        'mount'         => 0,
        'no_mount_fail' => 0,
    );
    foreach my $key ( keys %defaults ) {
        if ( !defined $param_hashref->{$key} ) {
            $param_hashref->{$key} = $defaults{$key};
        }
    }

    return @result;
}

sub _get_valid_parameters {
    return qw/path mount no_mount_fail/;
}

sub _validate_parameters {
    my ($param_hashref) = @_;
    my @result = ();

    unless ( _validate_path( $param_hashref->{'path'}, $param_hashref->{'mount'} ) ) {
        push @result, 'path';
    }

    foreach my $bin_param (qw/mount no_mount_fail/) {
        if ( defined $param_hashref->{$bin_param} ) {
            unless ( $param_hashref->{$bin_param} eq '1' || $param_hashref->{$bin_param} eq '0' ) {
                push @result, $bin_param;
            }
        }
    }

    return @result;
}

sub _check_params {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ($OPTS) = @_;

    my @missing = _missing_parameters($OPTS);
    if (@missing) {
        die Cpanel::Transport::Exception::MissingParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” is missing the following parameters: [list_and,_2]', __PACKAGE__, \@missing ),
            \@missing
        );
    }

    my @invalid = _validate_parameters($OPTS);
    if (@invalid) {
        die Cpanel::Transport::Exception::InvalidParameter->new(
            \@_, 0,
            $locale->maketext( '“[_1]” the following parameters were invalid: [list_and,_2]', __PACKAGE__, \@invalid ),
            \@invalid
        );
    }

    $OPTS->{'we_mounted_it'} = _mount_path_if_needed( $OPTS->{'path'}, $OPTS->{'mount'}, $OPTS->{'no_mount_fail'} );

    # Our local directory under the main directory,
    # This is what we return with pwd and update with chdir
    $OPTS->{'local_subdir'} = '/';
    return;
}

sub _validate_path {
    my ($path) = @_;

    # Not valid if it does not exist
    return 0 unless $path;

    # Not valid if it is a relative path
    return 0 unless $path =~ m|^/|;

    # Need to make sure the path is not under the backup directory
    my $conf_ref = Cpanel::Backup::Config::load();

    require Cpanel::Path::Dir;
    return 0 if Cpanel::Path::Dir::dir_is_below( $path, $$conf_ref{BACKUPDIR} );

    # Make sure the path is not a 'forbidden' directory
    return 0 unless ( Cpanel::Backup::Config::verify_backupdir($path) )[0];

    # Create the path if it does not yet exist
    File::Path::make_path( $path, { mode => $DIR_PERM } ) unless -d $path;

    # Check path permissions
    my $mode = ( stat $path )[2] & 07777;
    if ( $mode != $DIR_PERM ) {
        printf STDERR "Fixing permissions for “$path” to 0%o.\n", $DIR_PERM;
        chmod( 0711, $path ) or warn sprintf "Failed to chmod “$path” to 0%o permissions: $!", $DIR_PERM;
    }

    # Only return success if we can verify that we created the path
    if ( -d $path ) {
        return 1;
    }
    else {
        return 0;
    }
}

#
# Mount the drive if we are configured to and it is not
# already mounted.  Return whether we mounted it or not.
#
sub _mount_path_if_needed {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $path, $mount, $die_if_mount_fails ) = @_;

    # Do nothing if no need to mount
    if ( !$mount ) {
        print STDERR "Not configured to mount local directory\n";
        return 0;
    }

    # Do nothing if already mounted
    if ( Cpanel::BackupMount::backup_disk_is_mounted($path) ) {
        print STDERR "Mount if needed is enabled, but $path is already mounted\n";
        return 0;
    }

    # Mount it
    Cpanel::BackupMount::mount_backup_disk( $path, "LocalTransport" );

    # Validate that we mounted it
    # And if we did, then we are done here
    if ( Cpanel::BackupMount::backup_disk_is_mounted($path) ) {
        print STDERR "$path mounted successfully\n";
        return 1;
    }
    else {
        print STDERR "Failed to mount $path\n";
    }

    # If we failed to mount it, delete the bogus backup we may have created in the mount dir
    _remove_mount_lock($path);

    # Just return that we didn't mount if we aren't configured to error out
    return 0 unless $die_if_mount_fails;

    # We failed & we are not configured to go on with this
    die Cpanel::Transport::Exception->new( \@_, 0, $locale->maketext( 'Unable to mount “[_1]”.', $path ) );
}

sub DESTROY {
    my ($self) = @_;

    # Unmount if we had mounted
    if ( $self->{'we_mounted_it'} ) {
        Cpanel::BackupMount::unmount_backup_disk( $self->{'path'}, "LocalTransport" );
    }

    # If it is not mounted, then there shouldn't be a lock file
    unless ( Cpanel::BackupMount::backup_disk_is_mounted( $self->{'path'} ) ) {
        _remove_mount_lock( $self->{'path'} );
    }
    return;
}

#
# Removes the lock file if one has been left behind in the directory
# after unmounting.
#
sub _remove_mount_lock {
    my ($path) = @_;

    my $lock_file = File::Spec->catfile( $path, '.backupmount_locks' );

    unlink $lock_file if -e $lock_file;
    return;
}

#
# We'll return an empty string since we manage putting the files
# under the configured local path for this transport, the local path is absolute,
# a remote path to append here does not make sense.
#
sub get_path {
    my ($self) = @_;
    return '';
}

#
# Copy a file to our destination directory
#
sub _put {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $local, $remote ) = @_;

    my $dest = $self->_catfile($remote);

    Cpanel::LoadModule::load_perl_module('Cpanel::Umask');

    my $umask_obj = Cpanel::Umask->new(077);

    if ( File::Copy::cp( $local, $dest ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'Copying “[_1]” to “[_2]” failed: [_3]', $local, $dest, $! )
        );
    }
}

#
# Get a file from the destination directory
#
sub _get {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $remote, $local ) = @_;

    my $src = $self->_catfile($remote);

    Cpanel::LoadModule::load_perl_module('Cpanel::Umask');

    my $umask_obj = Cpanel::Umask->new(077);

    if ( File::Copy::cp( $src, $local ) ) {
        return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
    }
    else {
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'Copying “[_1]” to “[_2]” failed: [_3]', $src, $local, $! )
        );
    }
}

sub _ls {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $path ) = @_;

    my $dir = $self->_catdir($path);

    my @results;

    opendir( my $dh, $dir )
      or die Cpanel::Transport::Exception->new(
        \@_, 0,
        $locale->maketext( 'Unable to open “[_1]”: [_2]', $dir, $! )
      );

    while ( my $file_name = readdir $dh ) {

        # Skip these
        next if $file_name eq '.' || $file_name eq '..';

        # We need a full name
        my $full_name = File::Spec->catfile( $dir, $file_name );

        my ( $mode, $uid, $gid, $size, $mtime ) = ( stat($full_name) )[ 2, 4, 5, 7, 9 ];

        my ($user)  = getpwuid $uid;
        my ($group) = getgrgid $gid;

        my $file_info = {
            'filename' => $file_name,
            'mtime'    => $mtime,
            'perms'    => $mode & 07777,
            'user'     => $user,
            'group'    => $group,
        };

        if ( -d $full_name ) {
            $file_info->{'type'} = 'directory';
            $file_info->{'size'} = 0;
        }
        else {
            $file_info->{'type'} = 'file';
            $file_info->{'size'} = $size;
        }

        push @results, $file_info;
    }
    closedir $dh;

    return Cpanel::Transport::Response::ls->new( \@_, 1, 'OK', \@results );
}

sub _mkdir {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $path ) = @_;

    my $dir = $self->_catdir($path);

    eval {
        File::Path::make_path( $dir, { 'mode' => $DIR_PERM, 'error' => \my $err } );

        if (@$err) {
            my ( $file, $error ) = %{ $err->[0] };
            die Cpanel::Transport::Exception->new(
                \@_, 0,
                $locale->maketext( 'Could not make “[_1]”: [_2]', $dir, $error )
            );
        }
    };
    if ($@) {
        die Cpanel::Transport::Exception->new( \@_, 0, $@ );
    }

    # If the directory was not created, throw an error
    unless ( -d $dir ) {
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'Could not make “[_1]”.', $dir )
        );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _chdir {    ## no critic(RequireArgUnpacking) - passing all args for exception
    my ( $self, $path ) = @_;

    my $new_path;
    my @segments = split( '/', $path );

    # If the first one is empty, then it is an absolute path starting with a /
    if ( $segments[0] ) {

        # Relative path, start where we are
        $new_path = $self->{'local_subdir'};
    }
    else {

        # Absolute path, set to /
        $new_path = '/';

        # Get rid if null first param
        shift @segments;
    }

    # Handle each segment of the path individually
    # This will allow us to handle multiple ..'s
    foreach my $seg (@segments) {

        # Skip any blanks
        next unless $seg;

        # Skip '.', it is meaninless
        next if $seg eq '.';

        if ( $seg eq '..' ) {

            # Bump it up a directory
            ( undef, $new_path, undef ) = File::Spec->splitpath($new_path);

            # No trailing slash
            $new_path =~ s|/$||;
        }
        else {

            # Normal path segment, add it
            $new_path = File::Spec->catdir( $new_path, $seg );
        }

        # Get the real path this points to we can test it
        my $test_path = File::Spec->catdir( $self->{'path'}, $new_path );

        # If it doesnt exist, we can 'chdir' into it
        unless ( -d $test_path ) {
            die Cpanel::Transport::Exception->new(
                \@_, 0,
                $locale->maketext( 'Could not change working directory because “[_1]” is not a directory.', $new_path )
            );
        }
    }

    $self->{'local_subdir'} = $new_path;

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _rmdir {    ## no critic(RequireArgUnpacking) - passing all args for exception/response
    my ( $self, $path ) = @_;

    my $dir = $self->_catdir($path);

    File::Path::remove_tree( $dir, { 'error' => \my $err } );

    if (@$err) {
        my ( $file, $error ) = %{ $err->[0] };
        die Cpanel::Transport::Exception->new(
            \@_, 0,
            $locale->maketext( 'Could not remove “[_1]”: [_2]', $dir, $error )
        );
    }

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _delete {
    my ( $self, $path ) = @_;

    my $file = $self->_catfile($path);

    unlink $file or die Cpanel::Transport::Exception->new(
        \@_, 0,
        $locale->maketext( 'Could not delete “[_1]”: [_2]', $file, $! )
    );

    return Cpanel::Transport::Response->new( \@_, 1, 'OK' );
}

sub _pwd {
    my ($self) = @_;

    return Cpanel::Transport::Response->new( \@_, 1, 'OK', $self->{'local_subdir'} );
}

#
# Concatenate a file to the path specified for the transport
#
sub _catfile {
    my ( $self, $path ) = @_;

    return File::Spec->catfile( $self->{'path'}, $self->{'local_subdir'}, $path );
}

#
# Concatenate a directory to the path specified for the transport
#
sub _catdir {
    my ( $self, $path ) = @_;

    return File::Spec->catdir( $self->{'path'}, $self->{'local_subdir'}, $path );
}

1;
