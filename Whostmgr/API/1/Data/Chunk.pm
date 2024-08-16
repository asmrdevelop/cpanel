package Whostmgr::API::1::Data::Chunk;

# cpanel - Whostmgr/API/1/Data/Chunk.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Math ();

our $DEFAULT_CHUNK_SIZE = 100;

sub apply {
    my ( $args, $records, $state ) = @_;

    #Back out if the called function has already chunked/paginated the data.
    return 1 if delete $state->{'__chunked'};

    return 1 if !exists $args->{'enable'} || !$args->{'enable'};

    my $total = scalar @$records;
    my $start = $args->{'start'} ? int $args->{'start'} : 0;
    my $size  = int $args->{'size'};

    if ( exists $args->{'start'} ) {
        delete $args->{'select'};
    }
    if ( !defined $args->{'size'} || 1 > $size ) {
        $size = $DEFAULT_CHUNK_SIZE;
    }
    if ( exists $args->{'select'} && 0 < int $args->{'select'} ) {
        $start = $size * ( int $args->{'select'} - 1 ) + 1;
    }
    elsif ( exists $args->{'start'} && 0 < $start ) {
        $start = int $args->{'start'};
    }
    else {
        $start = 1;
    }
    if ( $start > $total ) {
        $start = 1;
    }

    my $end = $start + $size;

    if ( $end <= $total ) {
        splice @$records, $end - 1;
    }
    splice @$records, 0, $start - 1;

    if ( $args->{'verbose'} ) {
        $state->{'chunk'} = {
            'start'   => $start,
            'size'    => $size,
            'records' => $total,
            'current' => Cpanel::Math::ceil( $start / $size ),
            'chunks'  => Cpanel::Math::ceil( $total / $size ),
        };
    }

    return 1;
}

1;
