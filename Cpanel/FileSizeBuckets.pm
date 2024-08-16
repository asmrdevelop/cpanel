package Cpanel::FileSizeBuckets;

# cpanel - Cpanel/FileSizeBuckets.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::FileSizeBuckets

=head1 SYNOPSIS

    my $buckets_ar = sort_files_into_buckets( 5, \@paths );

=head1 DESCRIPTION

This module contains logic to divvy up files by their size into “buckets”
such that the “buckets” are as evenly-matched as possible in terms of total
file size.

=cut

#----------------------------------------------------------------------

use List::Util;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $buckets_ar = sort_files_into_buckets( $BUCKETS_COUNT, @PATHS )

Returns a reference to an array of “buckets” (arrays) of filenames. Each
“bucket” is as closely matched to the others as possible in terms of total
file size.

=cut

sub sort_files_into_buckets {
    my ( $max_buckets, @paths ) = @_;

    my %file_size;
    foreach my $path (@paths) {
        my $size = -s $path // do {
            warn "$path is not accessible because of an error: $!";
            next;
        };

        $file_size{$path} = $size;
    }

    # We need to assign the largest files first so that we know to group
    # smaller ones together to offset differences.
    my @sorted_paths = sort { $file_size{$b} <=> $file_size{$a} || $a cmp $b } keys %file_size;

    my @buckets;
    my @bucket_size = map { 0 } 1 .. $max_buckets;

    for my $path (@sorted_paths) {
        my $smallest_index = 0;
        for my $index ( 0 .. $#bucket_size ) {
            if ( $bucket_size[$index] < $bucket_size[$smallest_index] ) {
                $smallest_index = $index;
            }
        }

        push @{ $buckets[$smallest_index] }, $path;

        $bucket_size[$smallest_index] += $file_size{$path};
    }

    return \@buckets;
}

1;
