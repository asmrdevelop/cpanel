package Cpanel::ArrayFunc;

# cpanel - Cpanel/ArrayFunc.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = '1.4';

=encoding utf-8

=head1 NAME

Cpanel::ArrayFunc - Functions for manipulating arrays and array refs.

=cut

sub reorder ( $element, $rARRY ) {

    my $c = 0;
    @{$rARRY} = grep { $_ ne $element or ++$c and 0 } @{$rARRY};

    for ( 1 .. $c ) {
        push( @{$rARRY}, $element );
    }
    return 1;
}

#### returns one array of uniq items in one or more arrayrefs passed to it, non array ref items are ignored ####
#### did not call it uniq() becasue it behaves differently than List::MoreUtils::uniq() (on purpose) ####
sub uniq_from_arrayrefs (@list) {
    my %seen;
    my @final_values = ();
    my @temp         = map { @{$_} } grep { ref $_ eq 'ARRAY' } @list;
    foreach my $value (@temp) {
        unless ( defined( $seen{$value} ) ) {
            push @final_values, $value;
            $seen{$value} = 1;
        }
    }
    return wantarray ? @final_values : [@final_values];
}

#### pass one or more ArrayOfHashes and get back unique hashashrefefs (and non-hashashrefef's)
sub uniq_from_aoh (@list) {
    my @uniq;
    my %seen_refs_lookup;

  HASH:
    foreach my $hashref ( map { @{$_} } grep { ref $_ eq 'ARRAY' } @list ) {

        if ( ref $hashref ne 'HASH' ) {
            push @uniq, $hashref;
        }
        else {
            next HASH
              if exists $seen_refs_lookup{"$hashref"};    # double quotes for explicity not necessity
            $seen_refs_lookup{"$hashref"}++;              # double quotes for explicity not necessity

          SEEN:
            for my $seen_item (@uniq) {
                next SEEN
                  if ref $seen_item ne 'HASH';            # from first if(), this check saves us from having another array @seen
                next SEEN if ( keys %{$seen_item} != keys %{$hashref} );

                my $diff = 0;

              SEEN_CHECK:
                for my $seen_item_key ( keys %{$seen_item} ) {
                    if ( exists $hashref->{$seen_item_key} ) {

                        # complex value comparison removed, faster but error prone
                        if ( $seen_item->{$seen_item_key} ne $hashref->{$seen_item_key} ) {
                            $diff++;
                            last SEEN_CHECK;
                        }
                    }
                    else {
                        $diff++;
                        last SEEN_CHECK;
                    }
                }

                # if it's not different in that direction lets check the other direction:
                if ( !$diff ) {
                  HASH_CHECK:
                    for my $hashref_key ( keys %{$hashref} ) {
                        if ( exists $seen_item->{$hashref_key} ) {

                            # comples value comparison removed, faster but error prone
                            if ( $hashref->{$hashref_key} ne $seen_item->{$hashref_key} ) {
                                $diff++;
                                last HASH_CHECK;
                            }
                        }
                        else {
                            $diff++;
                            last HASH_CHECK;
                        }
                    }
                }

                # if $hashref is not different then it's the same as this SEEN and hence $hashref is a duplicate
                next HASH if !$diff;
            }

            # if we got this far the $hashref has not been seen yet and it is unique
            push @uniq, $hashref;
        }
    }

    return wantarray ? @uniq : \@uniq;
}

#FROM THE List::Util DOCUMENTATION, MODIFIED AS INDICATED

# All arguments are true
sub all { $_ || return $_ for @_; return 1 }    #FG: RETURN THE FALSE VALUE, IF ANY

# All arguments are false
sub none { $_ && return 0 for @_; return 1 }

# One argument is false
sub notall { $_ || return 1 for @_; return 0 }

# How many elements are true
sub true {
    return scalar grep { $_ } @_;
}

# How many elements are false
sub false {
    return scalar grep { !$_ } @_;
}

#TAKEN FROM List::Util
sub first ( $code, @list ) {

    foreach (@list) {
        return $_ if &{$code}();    # see comment at Cpanel::ArrayFunc::Map::mapfirst() below
    }

    return;
}

sub sum (@list) {
    my $sum;
    if (@list) {
        $sum = 0;
        $sum += $_ for @list;
    }

    return $sum;
}

# Smallest numerical value.
sub min {
    return ( sort { $a <=> $b } grep { defined } @_ )[0];
}

# Largest numerical value.
sub max {
    return ( sort { $a <=> $b } grep { defined } @_ )[-1];
}

1;
