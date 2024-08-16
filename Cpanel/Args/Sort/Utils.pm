package Cpanel::Args::Sort::Utils;

# cpanel - Cpanel/Args/Sort/Utils.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Exception ();

my %ipv4_cache;

#Returns a list of [ $column, $reverse, $method ],
#as derived from the arguments hashref. No munging of the data!
#
#Args are "column", "column_0", "method_0", "reverse_0", "column_1", etc.
sub parse_sorts {
    my ($rCFG) = @_;

    my ( @sorts, @column_ordinals );

    foreach my $param_key ( keys %$rCFG ) {

        # If a single sort is used, no numeric ordinal is required.
        # If multiple sorts are used, they need "_$ordinal" at the end,
        # e.g., “column_0”, “column_1”, etc.
        if ( $param_key eq 'column' ) {
            push @column_ordinals, undef;
        }
        elsif ( rindex( $param_key, 'column_', 0 ) == 0 ) {
            push @column_ordinals, substr( $param_key, 7 );
        }

    }

    # reverse the order so it behaves like SQL order by
    # NOTE: there can only be zero or one undef value in this list.
    @column_ordinals = sort { ( defined($a) cmp defined($b) ) || $a <=> $b } @column_ordinals;

  ORDINAL:
    foreach my $column_ordinal (@column_ordinals) {
        my $sort_column_key  = 'column';
        my $sort_method_key  = 'method';
        my $sort_reverse_key = 'reverse';

        if ( defined $column_ordinal ) {
            $sort_column_key  .= '_' . $column_ordinal;
            $sort_method_key  .= '_' . $column_ordinal;
            $sort_reverse_key .= '_' . $column_ordinal;
        }

        my $sort_column  = $rCFG->{$sort_column_key};
        my $sort_method  = $rCFG->{$sort_method_key};
        my $sort_reverse = $rCFG->{$sort_reverse_key} ? 1 : 0;

        push @sorts, [ $sort_column, $rCFG->{$sort_reverse_key} ? 1 : 0, $sort_method ];
    }

    return @sorts;
}

#----------------------------------------------------------------------
#For "Schwartzian" sorting with sort_transformed()
#NOTE: These are not useful outside this module because Perl
#makes $a and $b package globals within a sorter function.
#
#Also NOTE: (sort { $b <=> $a } @foo) is different from (reverse sort @foo).
#The former is what we want, regardless of its being faster,
#because it allows us to mimic SQL "ORDER BY" functionality by
#chaining multiple sorts together in reverse.
#----------------------------------------------------------------------
sub _sort_ipv4 {
    return ( $ipv4_cache{ $a->[1] } ||= pack( 'CCCC', split( /\./, $a->[1] ) ) ) cmp( $ipv4_cache{ $b->[1] } ||= pack( 'CCCC', split( /\./, $b->[1] ) ) );
}

sub _sort_ipv4_reverse {
    return ( $ipv4_cache{ $b->[1] } ||= pack( 'CCCC', split( /\./, $b->[1] ) ) ) cmp( $ipv4_cache{ $a->[1] } ||= pack( 'CCCC', split( /\./, $a->[1] ) ) );
}

sub _sort_lexicographic {
    return $a->[1] cmp $b->[1];
}

sub _sort_lexicographic_reverse {
    return $b->[1] cmp $a->[1];
}

sub _sort_numeric {
    return $a->[1] <=> $b->[1];
}

sub _sort_numeric_reverse {
    return $b->[1] <=> $a->[1];
}

sub _sort_numeric_zero_as_max {
    return $a->[1] != $b->[1]
      ? ( $a->[1] == 0 ? 1 : $b->[1] == 0 ? -1 : $a->[1] <=> $b->[1] )
      : $a->[1] <=> $b->[1];
}

sub _sort_numeric_zero_as_max_reverse {
    return $a->[1] != $b->[1]
      ? ( $b->[1] == 0 ? 1 : $a->[1] == 0 ? -1 : $b->[1] <=> $a->[1] )
      : $b->[1] <=> $a->[1];
}

#----------------------------------------------------------------------

sub is_valid_sort_method {
    my ($method) = @_;

    return ( $method && _get_sorter_cr($method) ) ? 1 : 0;
}

sub _get_sorter_cr {
    my ($method) = @_;

    return __PACKAGE__->can("_sort_$method");
}

#Sorts an array of hashes by one of its columns/fields.
#
#Append "_reverse" onto a method to get a reverse sort.
#
#NOTE: This is an IN-PLACE sort.
sub sort_by_column_and_method {
    my ( $records_ar, $column, $method ) = @_;

    my $sorter_cr;

    $sorter_cr = _get_sorter_cr($method);

    if ( !$sorter_cr ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid sort method.', [$method] );
    }

    @$records_ar = map { $_->[0] } sort $sorter_cr map { [ $_, $_->{$column} ] } @$records_ar;

    return;
}

1;
