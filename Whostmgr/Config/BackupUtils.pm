package Whostmgr::Config::BackupUtils;

# cpanel - Whostmgr/Config/BackupUtils.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub normalized_dir {
    my ( $dir, $appendSlash ) = @_;

    my $normalizedPath = $dir;

    my @array = split( //, $dir );
    if ( $array[-1] eq "/" ) {
        if ( !$appendSlash ) {
            $normalizedPath = substr( $dir, 0, length($dir) - 1 );
        }
    }
    else {
        if ($appendSlash) {
            $normalizedPath .= "/";
        }
    }

    return $normalizedPath;
}

sub get_parent_path {
    my ( $path, $appendSlash ) = @_;

    $path = normalized_dir( $path, 0 );

    my @array = split( /\//, $path );
    pop @array;

    my $out_path = join( '/', @array );

    return normalized_dir( $out_path, $appendSlash );
}

sub remove_base_path {
    my ( $base_path, $path ) = @_;

    $base_path = normalized_dir( $base_path, 1 );

    return if ( !( $path =~ m/^$base_path/ ) );

    return substr( $path, length($base_path) );
}

sub get_all_parent_paths {
    my ($relative_path) = @_;

    my @parts = split( /\//, $relative_path );

    my @output;
    my $dir;

    foreach my $part (@parts) {
        if ( !defined $dir ) {
            $dir = $part;
        }
        else {
            $dir = $dir . "/" . $part;
        }

        push( @output, $dir );
    }

    return @output;
}

1;
