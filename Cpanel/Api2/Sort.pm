package Cpanel::Api2::Sort;

# cpanel - Cpanel/Api2/Sort.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Args::Sort::Utils ();

our $DEFAULT_METHOD = 'lexicographic';

sub _get_sort_func_list {
    my ( $rCFG, $rAPI, $excludes_ar ) = @_;

    my %sort_args = map { rindex( $_, 'api2_sort_', 0 ) == 0 ? ( substr( $_, 10 ) => $rCFG->{$_} ) : () } keys %$rCFG;

    my @sorts = Cpanel::Args::Sort::Utils::parse_sorts( \%sort_args );

    for my $s ( reverse 0 .. $#sorts ) {
        my $cur_sort = $sorts[$s];
        my ( $sort_column, $sort_reverse, $sort_method ) = @$cur_sort;

        if ( !$sort_method ) {
            $sort_method = exists( $rAPI->{'sort_methods'} ) && $rAPI->{'sort_methods'}->{$sort_column};
        }

        #Legacy behavior. Ideally we'd just let this blow up.
        if ( !Cpanel::Args::Sort::Utils::is_valid_sort_method($sort_method) ) {
            $sort_method = $DEFAULT_METHOD;
        }

        $cur_sort->[2] = $sort_method;

        if ( 'ARRAY' eq ref $excludes_ar ) {
            for my $excl (@$excludes_ar) {
                next if $excl->{'column'} ne $sort_column;
                next if $excl->{'method'} ne $sort_method;

                my $exclude_reverse = $excl->{'reverse'} ? 1 : 0;
                next if $sort_reverse != $exclude_reverse;

                splice( @sorts, $s, 1 );
            }
        }
    }

    return \@sorts;
}

#Accepts $rCFG, $rAPI, and $excludes_ar
#Returns a list of hashes, keyed "column", "reverse", "method"
#
#NOTE: The sorter coderef is not useful outside this package
#because of sort()'s namespacing issues with $a and $b.
sub get_sort_func_list {
    return if !$_[0]->{'api2_sort'};

    my $simple_ar = _get_sort_func_list(@_);

    return [ map { my %new; @new{qw( column  reverse  method )} = @$_; \%new } @$simple_ar ];
}

sub apply {
    my ( $rCFG, $rDATA, $rAPI, $state ) = @_;
    my $sort_funcs = _get_sort_func_list( $rCFG, $rAPI, $state );

    if ( scalar @$rDATA <= 1 || !scalar @$sort_funcs ) {
        return wantarray ? @$rDATA : $rDATA;
    }

    my @sorted_data = @$rDATA;

    for my $sort_ar ( reverse @$sort_funcs ) {
        my ( $column, $reverse, $method ) = @$sort_ar;

        my $real_method = $method . ( $reverse ? '_reverse' : q{} );

        Cpanel::Args::Sort::Utils::sort_by_column_and_method( \@sorted_data, $column, $real_method );
    }

    return wantarray ? @sorted_data : \@sorted_data;
}

1;
