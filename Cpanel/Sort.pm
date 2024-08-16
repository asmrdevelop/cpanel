package Cpanel::Sort;

# cpanel - Cpanel/Sort.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#EACH SORT FIELD CAN BE:
#A SIMPLE HASH KEY OR ARRAY INDEX,
#A TRANSFORM SUBROUTINE REFERENCE,
#OR A HASH WITH ONE OR MORE OF THE FOLLOWING KEYS:
#   case:  CASE-SENSITIVITY (DEFAULT)
#   code:  TRANSFORM SUBROUTINE REFERENCE
#   desc:  DESCENDING ORDER
#   field: HASH KEY OR ARRAY INDEX. EXCLUDES "key"
#   num:   NUMERICAL SORTING
#   key:   (HASHES ONLY) SORT USING THE KEY, NOT THE VALUE. EXCLUDES "field"

use strict;
use warnings;

sub list_sort {
    my ( $list, @fields ) = @_;
    my @sorters = ();
    my @xformed = map { [$_] } @$list;    #INITIALIZE THE TRANSFORM LIST

    return $list unless @$list > 1;

    #ASSUME A SIMPLE LIST OR A LIST OF HASHES
    #SORTING OBJECTS IS NOT IMPLEMENTED BUT WOULD BE EASY TO DO. (PRACTICAL?)
    my $is_list_of_lists = ref $list->[0] eq 'ARRAY';

    #    my $is_list_of_objs  = ! $is_list_of_lists && Scalar::Util::blessed( $list->[0] );

    foreach my $f ( reverse 0 .. $#fields ) {
        my $cur_field = $fields[$f];
        my @xform_values;

        my $field_type = ref $cur_field;

        if ( $field_type eq 'HASH' ) {
            my $case_insensitive = exists $cur_field->{'case'} && !$cur_field->{'case'};

            if ( $cur_field->{'desc'} ) {
                if ( $cur_field->{'num'} ) {
                    unshift @sorters, sub { $b->[$f] <=> $a->[$f] };
                }
                else {
                    unshift @sorters, sub { $b->[$f] cmp $a->[$f] };
                }
            }
            else {
                if ( $cur_field->{'num'} ) {
                    unshift @sorters, sub { $a->[$f] <=> $b->[$f] };
                }
                else {
                    unshift @sorters, sub { $a->[$f] cmp $b->[$f] };
                }
            }

            if ( $cur_field->{'code'} ) {
                if ( exists $cur_field->{'field'} ) {
                    if ($is_list_of_lists) {
                        if ($case_insensitive) {
                            @xform_values = map { lc $cur_field->{'code'}( $_->[ $cur_field->{'field'} ] ) } @$list;
                        }
                        else {
                            @xform_values = map { $cur_field->{'code'}( $_->[ $cur_field->{'field'} ] ) } @$list;
                        }
                    }
                    else {
                        if ($case_insensitive) {
                            @xform_values = map { lc $cur_field->{'code'}( $_->{ $cur_field->{'field'} } ) } @$list;
                        }
                        else {
                            @xform_values = map { $cur_field->{'code'}( $_->{ $cur_field->{'field'} } ) } @$list;
                        }
                    }
                }
                else {
                    if ($case_insensitive) {
                        @xform_values = map { lc $cur_field->{'code'}($_) } @$list;
                    }
                    else {
                        @xform_values = map { $cur_field->{'code'}($_) } @$list;
                    }
                }
            }
            elsif ( exists $cur_field->{'field'} ) {
                if ($is_list_of_lists) {
                    if ($case_insensitive) {
                        @xform_values = map { lc $_->[ $cur_field->{'field'} ] } @$list;
                    }
                    else {
                        @xform_values = map { $_->[ $cur_field->{'field'} ] } @$list;
                    }
                }
                else {
                    if ($case_insensitive) {
                        @xform_values = map { lc $_->{ $cur_field->{'field'} } } @$list;
                    }
                    else {
                        @xform_values = map { $_->{ $cur_field->{'field'} } } @$list;
                    }
                }
            }
            elsif ($case_insensitive) {    #SIMPLE SORT, POSSIBLY CASE-INSENSITIVE
                @xform_values = map { lc $_ } @$list;
            }
        }
        else {
            unshift @sorters, sub { $a->[$f] cmp $b->[$f] };

            if ( $field_type eq 'CODE' ) {    #IMPLIES SORTING A SIMPLE LIST
                @xform_values = map { $cur_field->($_) } @$list;
            }
            else {                            #IMPLIES SORTING A LIST OF ARRAYS OR HASHES
                @xform_values =
                  $is_list_of_lists
                  ? map { $_->[$cur_field] } @$list
                  : map { $_->{$cur_field} } @$list;
            }
        }

        #IF IT'S A SIMPLE SORT WITH NO CASE TRANSFORM, NO NEED TO BOTHER HERE,
        #SINCE THE SORT WILL THEN JUST SORT ON THE INITIALIZED @xformed ARRAY,
        #WHICH IS IDENTICAL TO THE ORIGINAL.
        if (@xform_values) {
            foreach my $x ( 0 .. $#$list ) {
                unshift @{ $xformed[$x] }, $xform_values[$x];
            }
        }
    }

    if ( !scalar @sorters ) {
        push @sorters, sub { $a->[0] cmp $b->[0] };
    }

    my $val;
    my @sorted =
      map { $_->[-1] }
      sort {
        foreach (@sorters) {
            $val = $_->();
            last if $val;
        }
        $val
      } @xformed;

    return wantarray ? @sorted : \@sorted;
}

sub hash_sort {
    my ( $hash, @fields ) = @_;
    my @sorters = ();

    my @keys = keys %$hash;

    return $keys[0] if scalar @keys < 2;

    #THIS LATER GETS CONVERTED INTO A LIST OF LISTS.
    my %mid_xform = map { $_ => [ "$hash->{$_}", $_ ] } @keys;

    #ASSUME A SIMPLE HASH OR A HASH OF HASHES
    #SORTING OBJECTS IS NOT IMPLEMENTED BUT WOULD BE EASY TO DO. (PRACTICAL?)
    my $is_hash_of_lists = ref $hash->{ $keys[0] } eq 'ARRAY';

    foreach my $f ( reverse 0 .. $#fields ) {
        my $cur_field  = $fields[$f];
        my $field_type = ref $cur_field;

        if ( $field_type eq 'HASH' ) {
            my $case_insensitive = exists $cur_field->{'case'} && !$cur_field->{'case'};

            if ( $cur_field->{'desc'} ) {
                if ( $cur_field->{'num'} ) {
                    unshift @sorters, sub { $b->[$f] <=> $a->[$f] };
                }
                else {
                    unshift @sorters, sub { $b->[$f] cmp $a->[$f] };
                }
            }
            else {
                if ( $cur_field->{'num'} ) {
                    unshift @sorters, sub { $a->[$f] <=> $b->[$f] };
                }
                else {
                    unshift @sorters, sub { $a->[$f] cmp $b->[$f] };
                }
            }

            if ( $cur_field->{'code'} ) {
                if ( exists $cur_field->{'field'} ) {
                    if ($is_hash_of_lists) {
                        if ($case_insensitive) {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, lc $cur_field->{'code'}( $hash->{$key}->[ $cur_field->{'field'} ] );
                            }
                        }
                        else {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, $cur_field->{'code'}( $hash->{$key}->[ $cur_field->{'field'} ] );
                            }
                        }
                    }
                    else {
                        if ($case_insensitive) {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, lc $cur_field->{'code'}( $hash->{$key}->{ $cur_field->{'field'} } );
                            }
                        }
                        else {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, $cur_field->{'code'}( $hash->{$key}->{ $cur_field->{'field'} } );
                            }
                        }
                    }
                }
                else {
                    if ( $cur_field->{'key'} ) {
                        if ($case_insensitive) {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, lc $cur_field->{'code'}($key);
                            }
                        }
                        else {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, $cur_field->{'code'}($key);
                            }
                        }
                    }
                    else {
                        if ($case_insensitive) {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, lc $cur_field->{'code'}( $hash->{$key} );
                            }
                        }
                        else {
                            foreach my $key ( keys %$hash ) {
                                unshift @{ $mid_xform{$key} }, $cur_field->{'code'}( $hash->{$key} );
                            }
                        }
                    }
                }
            }
            elsif ( exists $cur_field->{'field'} ) {
                if ($is_hash_of_lists) {
                    if ($case_insensitive) {
                        foreach my $key ( keys %$hash ) {
                            unshift @{ $mid_xform{$key} }, lc $hash->{$key}->[ $cur_field->{'field'} ];
                        }
                    }
                    else {
                        foreach my $key ( keys %$hash ) {
                            unshift @{ $mid_xform{$key} }, $hash->{$key}->[ $cur_field->{'field'} ];
                        }
                    }
                }
                else {
                    if ($case_insensitive) {
                        foreach my $key ( keys %$hash ) {
                            unshift @{ $mid_xform{$key} }, $hash->{$key}->{ $cur_field->{'field'} };
                        }
                    }
                    else {
                        foreach my $key ( keys %$hash ) {
                            unshift @{ $mid_xform{$key} }, $hash->{$key}->{ $cur_field->{'field'} };
                        }
                    }
                }
            }
            elsif ( $cur_field->{'key'} ) {
                if ($case_insensitive) {
                    foreach my $key ( keys %$hash ) {
                        unshift @{ $mid_xform{$key} }, lc $key;
                    }
                }
                else {
                    foreach my $key ( keys %$hash ) {
                        unshift @{ $mid_xform{$key} }, $key;
                    }
                }
            }
            elsif ($case_insensitive) {
                foreach my $key ( keys %$hash ) {
                    unshift @{ $mid_xform{$key} }, lc $hash->{$key};
                }
            }
        }
        else {    #field is not a hash
            unshift @sorters, sub { $a->[$f] cmp $b->[$f] };

            if ( $field_type eq 'CODE' ) {
                foreach my $key ( keys %$hash ) {
                    unshift @{ $mid_xform{$key} }, $cur_field->( $hash->{$key} );
                }
            }
            else {    #field is neither a hash nor code
                if ($is_hash_of_lists) {
                    foreach my $key ( keys %$hash ) {
                        unshift @{ $mid_xform{$key} }, $hash->{$key}->[$cur_field];
                    }
                }
                else {
                    foreach my $key ( keys %$hash ) {
                        unshift @{ $mid_xform{$key} }, $hash->{$key}->{$cur_field};
                    }
                }
            }
        }
    }

    if ( !scalar @sorters ) {
        push @sorters, sub { $a->[0] cmp $b->[0] };
    }

    my $val;
    my @sorted =
      map { $_->[-1] }
      sort {
        foreach (@sorters) {
            $val = $_->();
            last if $val;
        }
        $val
      } values %mid_xform;

    return wantarray ? @sorted : \@sorted;
}

1;
