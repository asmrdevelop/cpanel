package Cpanel::Api2::Filter;

# cpanel - Cpanel/Api2/Filter.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Args::Filter::Utils ();

our $DEFAULT_TYPE = 'contains';

#Returns a list of arrays, each of which is: [ column, type, term ]
sub get_filters {
    my $rCFG     = shift;
    my $excludes = shift;

    my @real_filters;

    if ( $rCFG->{'api2_filter'} ) {
        my %filter_args = map { rindex( $_, 'api2_filter_', 0 ) == 0 ? ( substr( $_, 12 ) => $rCFG->{$_} ) : () } keys %$rCFG;

        my @filters = Cpanel::Args::Filter::Utils::parse_filters( \%filter_args );

        my %exclude_lookup;
        if ( 'ARRAY' eq ref $excludes ) {
            %exclude_lookup = map { join( ' ', @$_ ) => undef } @$excludes;
        }

        foreach my $f ( 0 .. $#filters ) {
            my $filter_ar = $filters[$f];

            #coerce the 'type'
            $filter_ar->[1] ||= $DEFAULT_TYPE;

            my ( $column, $type, $term ) = @$filter_ar;

            #Skip invalid filters.
            next if !length $column;
            next if !Cpanel::Args::Filter::Utils::is_valid_filter_type( $filter_ar->[1] );
            next if $type ne 'eq' && !length $term;

            #Prevent redoing filters that are already done.
            my $filter_exclude_key = join( ' ', @$filter_ar );
            next if exists $exclude_lookup{$filter_exclude_key};

            push @real_filters, $filter_ar;
        }
    }

    return wantarray ? @real_filters : \@real_filters;
}

sub apply {
    my ( $rCFG, $rDATA, $apiref, $filtered_ar, $state_hr ) = @_;

    if (@$rDATA) {
        my @filters_to_apply = get_filters( $rCFG, $filtered_ar );

        if (@filters_to_apply) {
            $state_hr->{'records_before_filter'} = scalar @$rDATA;
        }

        for my $filter_ar (@filters_to_apply) {
            Cpanel::Args::Filter::Utils::filter_by_column_type_term(
                $rDATA,
                @$filter_ar,
            );
        }
    }

    return wantarray ? @$rDATA : $rDATA;
}

1;
