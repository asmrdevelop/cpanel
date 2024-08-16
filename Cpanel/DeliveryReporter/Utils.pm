package Cpanel::DeliveryReporter::Utils;

# cpanel - Cpanel/DeliveryReporter/Utils.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#Args: $func_args_hr, $filters_ar (from get_filters())
#Spits out a hash of opts for Cpanel::DeliveryReporter::query() to accept.
sub convert_filters_for_query {
    my ( $func_args_hr, $filters_ar ) = @_;
    for (@$filters_ar) {
        my ( $field, $type, $term ) = @$_;

        $field = 'all' if $field eq '*';    #special case

        if ( $type eq 'lt' ) {
            $func_args_hr->{ 'max' . $field } = _int($term) - 1;
        }
        elsif ( $type eq 'gt' ) {
            $func_args_hr->{ 'min' . $field } = _int($term) + 1;
        }
        elsif ( $type eq '==' ) {
            $func_args_hr->{ 'min' . $field } = $func_args_hr->{ 'max' . $field } = _int($term);
        }
        else {
            my $counter = 0;
            while ( exists $func_args_hr->{ $field . '-' . $counter } ) {
                $counter++;
            }
            @{$func_args_hr}{ $field . '-' . $counter, "searchmatch_$field" . '-' . $counter } = ( $term, $type );
        }
    }

    return $func_args_hr;
}

sub _int {
    return 0 unless defined $_[0] && $_[0] =~ qr{^\s*(-?[0-9]+)};
    return int($1);
}

1;
