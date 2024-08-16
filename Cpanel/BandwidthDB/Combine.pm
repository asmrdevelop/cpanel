package Cpanel::BandwidthDB::Combine;

# cpanel - Cpanel/BandwidthDB/Combine.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Context ();

#----------------------------------------------------------------------
#This is used to combine data "sampled" at e.g., 5-minute, hourly, and daily
#intervals. It can convert, for example, data from 1-hour and 10-minute
#intervals into a single stream of 10-minute interval entries.
#
#This works by assigning the entirety of the big interval’s data into
#a "filler" sample at the first block of small-interval data within
#the earliest "intersection" between low-interval and big-interval data.
#If the datasets contain multiple big-intervals of overlap, ONLY the least
#of these will reflect a "combination".
#
#A few assumptions are in play here:
#   - Big-interval data starts no later than small-interval data.
#   - Big-interval data ends no later than small-interval data.
#
#   - The sum of small-interval data within a given big interval will
#       be equal to (or less than) the corresponding big interval datum.
#
#Note that the idea of "interval" is not a strict one; the distance between
#the samples can actually vary. The only "interval" we care about is the
#earliest "overlap" between the two.
#
#Parameters are given as a list of arrayrefs, SORTED BY LOWEST $stamp:
#   [ [ $stamp => $amount ], [ $stamp2 => $amount2 ], .. ],
#   [ [ $stamp => $amount ], [ $stamp2 => $amount2 ], .. ],
#   ...
#
#NB: "sorted by lowest $stamp" implies sorted DESCENDING by interval size.
#So, the first dataset should be daily, then hourly, then 5-minute, etc.
#
#(The actual size of the interval doesn't really matter; strictly speaking,
#it's not even necessary for the sample times to be evenly spaced.)
#
#NOTE: This currently does NOT duplicate data structures in the return. This is
#in order to minimize memory usage; the caveat is that it is possible, after
#executing this function, to alter the return by altering the input,
#or vice-versa.
#----------------------------------------------------------------------

#Use when the timestamps are to be compared numerically.
sub combine_samples_with_numeric_time {
    my @datasets = @_;

    return _combine_samples(
        time_template => "% Xs",       #left-pad
        data_ar       => \@datasets,
    );
}

#Use when the timestamps are to be compared as strings.
sub combine_samples_with_string_time {
    my @datasets = @_;

    return _combine_samples(
        time_template => "% -Xs",      #right-pad
        data_ar       => \@datasets,
    );
}

sub _combine_samples {
    my (%opts) = @_;

    Cpanel::Context::must_be_list();

    my $datasets_ar = $opts{'data_ar'};

    my $smallest_interval_ar = pop @$datasets_ar;
    while (@$datasets_ar) {
        $smallest_interval_ar = _combine_two_datasets(
            $opts{'time_template'},
            pop @$datasets_ar,
            $smallest_interval_ar,
        );
    }

    return @{$smallest_interval_ar};
}

#Sorry for the goofiness of this logic. It would be much simpler without
#the need to accommodate string timestamps. Because of this, we can't do things
#like use modulo or add/subtract timestamps.
#
#The flexibility that this gives, though, allows uneven timestamps to parse
#through this just fine. (However useful that may be...)
#
sub _combine_two_datasets {
    my ( $time_tplt, $big_samples_ar, $small_samples_ar ) = @_;

    my $max_time_length = length( $small_samples_ar->[-1][0] );
    $time_tplt =~ s<X><$max_time_length>;

    my $earliest_big_time   = sprintf( $time_tplt, $big_samples_ar->[0][0] );
    my $earliest_small_time = sprintf( $time_tplt, $small_samples_ar->[0][0] );

    if ( $earliest_small_time le $earliest_big_time ) {

        #Nothing to do since the small-interval samples
        #start before the big-interval ones, and we assume
        #that the big interval ones end no later. (See above.)
        return $small_samples_ar;
    }

    my @composite_samples;

    #This is the time at which we *might* create a "filler" sample.
    my $unpadded_combination_sample_time;

    my $one_after_combination_sample_time;

    for my $big_sample_ar ( @{$big_samples_ar} ) {
        my $padded_stamp = sprintf( $time_tplt, $big_sample_ar->[0] );
        if ( $padded_stamp gt $earliest_small_time ) {
            $one_after_combination_sample_time = $padded_stamp;
            last;
        }
        $unpadded_combination_sample_time = $big_sample_ar->[0];
    }

    my $combination_sample_time = sprintf( $time_tplt, $unpadded_combination_sample_time );

    for my $big_sample_ar ( @{$big_samples_ar} ) {
        my $cur_big_time = sprintf( $time_tplt, $big_sample_ar->[0] );

        if ( $cur_big_time lt $combination_sample_time ) {
            push @composite_samples, $big_sample_ar;
        }
        elsif ( $cur_big_time eq $combination_sample_time ) {

            #If the below test is true, then there is no need to
            #add a "filler" sample.
            last if $earliest_small_time eq $combination_sample_time;

            my $new_sample = $big_sample_ar->[1];

            for my $small_sample_ar ( @{$small_samples_ar} ) {

                #NB: We assumed that the big dataset starts NO LATER.
                #
                if ($one_after_combination_sample_time) {
                    last if sprintf( $time_tplt, $small_sample_ar->[0] ) ge $one_after_combination_sample_time;
                }

                $new_sample -= $small_sample_ar->[1];
            }

            if ($new_sample) {
                push @composite_samples, [ $unpadded_combination_sample_time => $new_sample ];
            }

            last;
        }

        #Can this even be reached? Leave it in as a safety-net.
        else {
            last;
        }
    }

    push @composite_samples, @{$small_samples_ar};

    return \@composite_samples,;
}

1;
