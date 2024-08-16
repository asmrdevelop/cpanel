package Cpanel::FileUtils::Dir;

# cpanel - Cpanel/FileUtils/Dir.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();

#To avoid needing Errno.pm
use constant _ENOENT => 2;

sub directory_has_nodes {
    return directory_has_nodes_if_exists( $_[0] ) // do {
        local $! = _ENOENT();
        die _opendir_err( $_[0] );
    };
}

sub directory_has_nodes_if_exists {
    my ($dir) = @_;

    local $!;

    opendir my $dh, $dir or do {
        if ( $! == _ENOENT() ) {
            return undef;
        }

        die _opendir_err($dir);
    };

    local $!;

    my $has_nodes = 0;
    while ( my $node = readdir $dh ) {
        next if $node eq '.' || $node eq '..';
        $has_nodes = 1;
        last;
    }

    _check_for_readdir_error($dir) if !$has_nodes;
    _closedir( $dh, $dir );

    return $has_nodes;
}

#Same as get_directory_nodes() but returns undef if not exists.
sub get_directory_nodes_if_exists {
    my ($dir) = @_;

    local $!;

    # Avoid generating an exception for an expected case (dir ENOENT)
    # as its too expensive
    if ( opendir my $dh, $dir ) {
        return _read_directory_nodes( $dh, $dir );
    }
    elsif ( $! != _ENOENT() ) {
        die _opendir_err($dir);
    }
    return undef;
}

#Returns an array reference; excludes . and ..
sub get_directory_nodes {
    return _read_directory_nodes( _opendir( $_[0] ), $_[0] );
}

#Returns an array reference; excludes . and ..
sub _read_directory_nodes {    ## no critic qw(Subroutines::RequireArgUnpacking) -- used in loops
                               # $_[0] == $dir_handle
                               # $_[1] == $path
    local $!;
    my @nodes = grep { $_ ne '.' && $_ ne '..' } readdir( $_[0] );
    _check_for_readdir_error( $_[0] );
    _closedir( $_[0], $_[1] );
    return \@nodes;
}

sub _check_for_readdir_error {

    # FIXED in Perl 5.20+
    # cf. https://rt.perl.org/Public/Bug/Display.html?id=118651
    if ( $! && ( $^V >= v5.20.0 ) ) {
        die Cpanel::Exception::create( 'IO::DirectoryReadError', [ path => $_[0], error => $! ] );
    }

    return;
}

sub _opendir {
    local $!;
    opendir my $dh, $_[0] or do {
        die _opendir_err( $_[0] );
    };

    return $dh;
}

# 0 = directory handle
# 1 = path
sub _closedir {
    local $!;
    closedir $_[0] or do {
        die Cpanel::Exception::create( 'IO::DirectoryCloseError', [ path => $_[1], error => $! ] );
    };

    return;
}

sub _opendir_err {
    return Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $_[0], error => $! ] );
}

1;
