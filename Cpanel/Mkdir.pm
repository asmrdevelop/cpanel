package Cpanel::Mkdir;

# cpanel - Cpanel/Mkdir.pm                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Umask ();

use Cpanel::Autodie   ();
use Cpanel::Exception ();

#----------------------------------------------------------------------
# XXX XXX XXX ----- READ ME FIRST!!!!!
#
# This module assumes that all parent directories of a newly-created
# directory need to have the same permissions as the “leaf” directory.
# That’s not a safe assumption by any stretch.
#
# If you use this code, please ensure that the parent directories
# already exist.
#----------------------------------------------------------------------

#----------------------------------------------------------------------
#NOTE: No effort is made at race safety or non-traversal of symlinks.
#Caveat emptor!
#
#This will, like File::Path::make_path(), create “intermediary” directories.
#as necessary to ensure that the full path exists and refers to a directory.
#“Intermediary” directories will be created with the given $mode.
#
#Returns:
#   -1 if it chmod()ed the directory
#   otherwise, the number of directories created (i.e., 0 or more)
#
#An appropriate exception is thrown on error. This includes if the path
#already exists and is not a directory.
#
#TODO: Extend this to match up with Test::Filesys::make_structure() so
#that we can declaratively create deep structures.
#
sub ensure_directory_existence_and_mode {
    my ( $path, $mode ) = @_;

    if ( Cpanel::Autodie::exists($path) && -d _ ) {
        return _chmod_or_die( $path, $mode );    # The caller MUST always stat $path before calling _chmod_or_die
    }

    my @path_split = split m</>, $path;

    my $parent_count = ( $#path_split - 1 );
    my $parent_path  = join( '/', @path_split[ 0 .. $parent_count ] );
    my $umask;
    if ( defined $mode ) {
        $umask ||= Cpanel::Umask->new(0000);
    }

    # If the parent exists, we can skip walking the
    # file system and just create it.
    if ( Cpanel::Autodie::exists($parent_path) && -d _ ) {
        return _mkdir_or_chmod_if_exists_or_die( $path, $mode );
    }

    # The parent dir did not exist, walk the filesystem and
    # create each dir as needed
    my $count = 0;
    for my $i ( 1 .. $#path_split ) {
        my $interim_path = join( '/', @path_split[ 0 .. $i ] );

        next if -d $interim_path;
        $count += _mkdir_or_chmod_if_exists_or_die( $interim_path, $mode );
    }

    return $count;
}

sub _mkdir_or_chmod_if_exists_or_die {
    my ( $path, $mode ) = @_;

    return 1 if _mkdir( $path, $mode );

    if ( $! == _EEXIST() && -d $path ) {

        # The directory was created by another process
        # so we just need to ensure the permissions
        _chmod_or_die( $path, $mode );    # The caller MUST always stat $path before calling _chmod_or_die
        return 0;
    }

    die Cpanel::Exception::create( 'IO::DirectoryCreateError', [ path => $path, mask => $mode, error => $! ] );
}

# $_[0] = path
# $_[1] = mode
sub _mkdir {
    return ( defined $_[1] ? mkdir( $_[0], $_[1] ) : mkdir( $_[0] ) );
}

# The caller MUST always stat $path before
# calling this internal function
sub _chmod_or_die {
    my ( $path, $mode ) = @_;
    if ( defined($mode) && ( ( stat(_) )[2] & 07777 ) != ( $mode & 07777 ) ) {
        Cpanel::Autodie::chmod( $mode, $path );
        return -1;
    }
    return 0;
}

sub _EEXIST { return 17; }

1;
