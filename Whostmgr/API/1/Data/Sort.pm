package Whostmgr::API::1::Data::Sort;

# cpanel - Whostmgr/API/1/Data/Sort.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Whostmgr::API::1::Data::Utils ();

my %or_cache;
my %ipv4_cache;

#For testing.
#NOTE: No need to clear %ipv4_cache.
sub _clear_cache {
    %or_cache = ();
}

sub _get_sorter {
    my ( $fieldspec, $method, $reverse ) = @_;
    my $drill_into = sub {
        return Whostmgr::API::1::Data::Utils::evaluate_fieldspec( $fieldspec, shift );
    };

    my $funcs = {
        'ipv4' => sub {
            $or_cache{$a} ||= $drill_into->($a);
            $or_cache{$b} ||= $drill_into->($b);

            ( $ipv4_cache{ $or_cache{$a} } ||= pack( 'CCCC', split( /\./, $or_cache{$a} ) ) ) cmp( $ipv4_cache{ $or_cache{$b} } ||= pack( 'CCCC', split( /\./, $or_cache{$b} ) ) );
        },
        'ipv4_reverse' => sub {
            $or_cache{$a} ||= $drill_into->($a);
            $or_cache{$b} ||= $drill_into->($b);

            ( $ipv4_cache{ $or_cache{$b} } ||= pack( 'CCCC', split( /\./, $or_cache{$b} ) ) ) cmp( $ipv4_cache{ $or_cache{$a} } ||= pack( 'CCCC', split( /\./, $or_cache{$a} ) ) );
        },

        'lexicographic' => sub {
            ( $or_cache{$a} ||= $drill_into->($a) ) cmp( $or_cache{$b} ||= $drill_into->($b) );
        },
        'lexicographic_reverse' => sub {
            ( $or_cache{$b} ||= $drill_into->($b) ) cmp( $or_cache{$a} ||= $drill_into->($a) );
        },
        'lexicographic_caseless' => sub {
            lc( $or_cache{$a} ||= $drill_into->($a) ) cmp lc( $or_cache{$b} ||= $drill_into->($b) );
        },
        'lexicographic_caseless_reverse' => sub {
            lc( $or_cache{$b} ||= $drill_into->($b) ) cmp lc( $or_cache{$a} ||= $drill_into->($a) );
        },

        'numeric' => sub {
            ( $or_cache{$a} ||= $drill_into->($a) ) <=> ( $or_cache{$b} ||= $drill_into->($b) );
        },
        'numeric_reverse' => sub {
            ( $or_cache{$b} ||= $drill_into->($b) ) <=> ( $or_cache{$a} ||= $drill_into->($a) );
        },

        'numeric_zero_as_max' => sub {
            my $temp_a = ( $or_cache{$a} ||= $drill_into->($a) );
            my $temp_b = ( $or_cache{$b} ||= $drill_into->($b) );
            my $result = $temp_a <=> $temp_b;
            if ( $temp_a != $temp_b ) {
                $result = 1  if ( $temp_a == 0 );
                $result = -1 if ( $temp_b == 0 );
            }
            $result;
        },
        'numeric_zero_as_max_reverse' => sub {
            my $temp_b = ( $or_cache{$b} ||= $drill_into->($b) );
            my $temp_a = ( $or_cache{$a} ||= $drill_into->($a) );
            my $result = $temp_b <=> $temp_a;
            if ( $temp_a != $temp_b ) {
                $result = 1  if ( $temp_b == 0 );
                $result = -1 if ( $temp_a == 0 );
            }
            $result;
        },
    };

    $method = 'lexicographic' if ( !exists $funcs->{$method} || $method eq 'alphabet' );
    my $full_method = $method;
    if ($reverse) {
        $full_method .= '_reverse';
    }

    return {
        'func'    => $funcs->{$full_method},
        'method'  => $method,
        'reverse' => $reverse ? 1 : 0
    };
}

sub _get_sort_func_list {
    my ( $args, $state ) = @_;
    my @sort_funcs;

    # reverse the order so it behaves like SQL order by
    foreach my $id ( reverse sort keys %$args ) {
        next if 'HASH' ne ref $args->{$id};
        next if !defined Whostmgr::API::1::Data::Utils::id_is_valid($id);

        my $fs        = $args->{$id};
        my $fieldspec = Whostmgr::API::1::Data::Utils::fieldspec_is_valid( $fs->{'field'} );
        next if !defined $fieldspec;

        my $sorter = _get_sorter( $fs->{'field'}, $fs->{'method'}, $fs->{'reverse'} );

        if ( $args->{'verbose'} ) {
            if ( !exists $state->{'sort'} ) {
                $state->{'sort'} = {};
            }
            $state->{'sort'}->{$id} = {
                'field'   => $fieldspec,
                'method'  => $sorter->{'method'},
                'reverse' => $sorter->{'reverse'},
            };
        }

        if ( !$fs->{'__done'} ) {    # We only apply the sort function if the data has not already been pre-sorted by the function.
            push @sort_funcs, $sorter->{'func'};
        }
    }

    return \@sort_funcs;
}

sub apply {
    my ( $args, $records, $state ) = @_;
    return 1 if !exists $args->{'enable'} || !$args->{'enable'};

    my $sort_funcs = _get_sort_func_list( $args, $state );

    if ( 0 == scalar @$sort_funcs ) {
        return 1;
    }
    elsif ( 1 == scalar @$sort_funcs ) {
        my $sort_func = shift @$sort_funcs;
        @$records = sort $sort_func @$records;
    }
    else {
        my @sorted_records;
        for ( my $i = 0; $i < scalar @$sort_funcs; ++$i ) {
            my $sort_func = shift @$sort_funcs;
            @sorted_records = sort $sort_func ( $i == 0 ? @$records : @sorted_records );
        }
        @$records = @sorted_records;
    }

    return 1;
}

1;
