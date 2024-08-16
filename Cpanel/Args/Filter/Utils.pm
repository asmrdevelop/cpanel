package Cpanel::Args::Filter::Utils;

# cpanel - Cpanel/Args/Filter/Utils.pm             Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception ();

#Always local()ized; used for DRY and to reduce argument-passing.
our $_term;

#NB: An empty 'matches' does something COMPLETELY unexpected!
our @EMPTY_TERM_IS_NO_OP = qw(
  contains
  begins
  ends
  matches
);

=head1 NAME

Cpanel::Args::Filter::Utils

=head1 DESCRIPTION

This module contains all the sugar needed to filter data structures based on
the ARRAYREF returned by Cpanel::Args' "filters" method, which contains
Cpanel::Args::Filters objects.

This may or may not be a design pattern you are used to, as recent idiomatic
perls generally would prefer data that requires sugar to properly act upon
your data instead be as a part of the object returned, instead of an ARRAYREF.

In any case, instead of doing something like $args->filters->process($data),
you must instead call various subroutines from this module to process the data
which you wish to filter, as will be described below in the SYNOPSIS and
SUBROUTINES sections. Refactors towards a direction described above are left
as an exercise to the reader, but more than likely would involve accepting
either $data or a $coderef, as the latter would likely be required in
performance critical contexts, as processing data after gathering it instead
of as you gather it is generally going to result in duplicated loops over
your data to say the least.

As a reminder, you should be running performance analyses on your code, as upon
a read of both the below "ways to do it" and the code it invokes should
immediately suggest that when many filters have been passed in, it may be more
efficient to filter *after* the data has been gathered instead of as you
gather it. That said, this is likely not to be a often done thing. In most
cases you only want to filter based on one set of criteria.

=head1 SYNOPSIS

    use Cpanel::Args::Filter::Utils ();

    # Process it after the work has been done.
    sub my_super_cool_uapi_method ( $args, $result ) {
        my $filters = $args->filters();
        ... # Do work that results in something looking like the following:
        my $return_ar = [
            'bozo' => 'clown',
            'foo'  => 'bar',
        ];
        foreach my $filter ( @$filters ) {
            Cpanel::Args::Filter::Utils::filter_by_column_type_term(
                $return_ar, $filter->column, $filter->type, $filter->term, 
            );
        }
        $result->data($return_ar);
        return 1;
    }

    # Or do it "in loop" for efficiency's sake:
    sub my_maybe_more_efficient_uapi_method ( $args, $result ) {
        my $filters = $args->filters();
        my @trapper_keeper;
        while ( get_things_from_backend($args) ) {
            my $thing = $_;
            next if check_value_for_column_versus_filters(
                $value, 'thing', $filters,
            );
            push @trapper_keeper, $thing;
        }
        ... # Do whatever you want with the @trapper_keeper past there
    }

=head1 SUBROUTINES

=cut

#Returns a list of arrays,
#as derived from the arguments hashref. No munging of the data!
#
#Each array is: [ column, type, term ]
sub parse_filters {
    my ($rCFG) = @_;

    my @filters;
    my @filter_ordinals;

    foreach my $param_key ( keys %$rCFG ) {

        # If a single filter is used, no numeric ordinal is required.
        # If multiple filters are used, they need "_$ordinal" at the end,
        # e.g., “column_0”, “column_1”, etc.
        if ( $param_key eq 'column' ) {
            push @filter_ordinals, undef;
        }
        elsif ( rindex( $param_key, 'column_', 0 ) == 0 ) {
            push @filter_ordinals, substr( $param_key, 7 );
        }
    }

    @filter_ordinals = sort { ( defined($a) cmp defined($b) ) || $a <=> $b } @filter_ordinals;

    foreach my $filter_ordinal (@filter_ordinals) {
        my $type_key   = 'type';
        my $column_key = 'column';
        my $term_key   = 'term';

        if ( defined $filter_ordinal ) {
            $type_key   .= '_' . $filter_ordinal;
            $column_key .= '_' . $filter_ordinal;
            $term_key   .= '_' . $filter_ordinal;
        }
        my $filter_ar = [ @{$rCFG}{ $column_key, $type_key, $term_key } ];

        push @filters, $filter_ar;
    }

    return @filters;
}

sub is_valid_filter_type {
    my ($type) = @_;

    return ( $type && _get_filter_cr($type) ) ? 1 : 0;
}

sub _get_filter_cr {
    my ($type) = @_;

    return __PACKAGE__->can("_filter_$type");
}

#Removes list items that don't fit the column/type/term.
#Returns the removed elements as an arrayref.
sub filter_by_column_type_term {
    my ( $records_ar, $column, $type, $term ) = @_;

    #See comment by @EMPTY_TERM_IS_NO_OP.
    return [] if !length $term && grep { $_ eq $type } @EMPTY_TERM_IS_NO_OP;

    my $filter_func_cr = _get_filter_cr($type);

    if ( !$filter_func_cr ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid filter type.', [$type] );
    }

    local $_term = $term;

    if ( column_is_wildcard($column) ) {
        return _apply_wildcard( $records_ar, $filter_func_cr );
    }

    return _apply_non_wildcard( $records_ar, $column, $filter_func_cr );
}

=head2 check_value_for_column_versus_filters

Subroutine for figuring out whether or not the value and column you passed in
matches the passed in filters.

Accepts:
* $value   - What will be compared versus $filter->term() via $filter->type().
* $column  - What to compare versus $filter->column() via string equivalence.
* $filters - ARRAYREF of Cpanel::Args::Filter objects.

Returns 0 or 1 based on whether or not:
* The filter matched the column and passed in value.
* The filter was garbage (not wrong type, etc.).

=head3 SEE ALSO

Cpanel::Args::Filter - The objects in question we filter via
Cpanel::Args         - Get the $filters arrayref from the `filters` method.

=cut

sub check_value_for_column_versus_filters ( $value, $column, $filters ) {
    return 0 if ref $filters ne 'ARRAY';
    my $matched;

    my $matched_any = 0;
    foreach my $filter (@$filters) {
        next if ref $filter ne 'Cpanel::Args::Filter';
        next if $filter->column ne $column;
        my $checker_cr = _get_filter_cr( $filter->type() );
        next if ref $checker_cr ne 'CODE';

        # Calling convention exists but is space case. Accomodate it via local.
        local $_term = $filter->term();
        local $_     = $value;
        if ( $checker_cr->() ) {
            $matched_any = 1;
        }
        else {
            return 0;
        }
    }
    return $matched_any;
}

sub column_is_wildcard {
    my ($column) = @_;

    return ( $column eq '*' ) ? 1 : 0;
}

sub _apply_non_wildcard {
    my ( $records_ar, $column, $filter_func_cr ) = @_;

    my @removed;

  RECORD:
    for my $r ( reverse 0 .. $#$records_ar ) {
        for ( $records_ar->[$r]{$column} ) {
            if ( ref eq 'ARRAY' ) {
                for (@$_) {
                    next RECORD if $filter_func_cr->();
                }
            }
            else {
                next RECORD if $filter_func_cr->();
            }

            unshift @removed, splice( @$records_ar, $r, 1 );
        }
    }

    return \@removed;
}

sub _apply_wildcard {
    my ( $records_ar, $filter_func_cr ) = @_;

    my ( $record, @removed );

  RECORD:
    for my $r ( reverse 0 .. $#$records_ar ) {
        $record = $records_ar->[$r];
        for ( values %$record ) {
            if ( ref eq 'ARRAY' ) {
                for (@$_) {
                    next RECORD if $filter_func_cr->();
                }
            }
            else {
                next RECORD if $filter_func_cr->();
            }
        }

        unshift @removed, splice( @$records_ar, $r, 1 );
    }

    return \@removed;
}

#----------------------------------------------------------------------
#Assume:
#   $_ is the value to test
#   $_term is the term

sub _filter_contains {
    return m/\Q$_term\E/i;
}

sub _filter_begins {
    return m/\A\Q$_term\E/i;
}

sub _filter_ends {
    return m/\Q$_term\E\z/i;
}

sub _filter_matches {
    return m{$_term};
}

sub _filter_eq {
    return $_ eq $_term;
}

sub _filter_ne {
    return $_ ne $_term;
}

sub _filter_lt {
    return 1 if defined $_ && tr<A-Z><a-z>r eq 'unlimited';    # note - should return 0... preserve behavior
    return $_ < $_term;
}

sub _filter_lt_handle_unlimited {
    return tr<A-Z><a-z>r ne 'unlimited' && $_ != 0 && $_ < $_term;
}

sub _filter_gt {
    return if defined $_ && tr<A-Z><a-z>r eq 'unlimited';      # note - should return 1... preserve behavior
    return $_ > $_term;
}

sub _filter_gt_handle_unlimited {
    return tr<A-Z><a-z>r eq 'unlimited' || $_ == 0 || $_ > $_term;
}

#----------------------------------------------------------------------

1;
