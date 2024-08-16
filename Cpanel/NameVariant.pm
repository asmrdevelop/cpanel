package Cpanel::NameVariant;

# cpanel - Cpanel/NameVariant.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#This appends a numeral after the passed-in "name" until it arrives at a
#variant that satisfies the "test".
#
#If we reach max_length, then this starts chopping off bytes from the "name".
#
#If we end up chopping off the entire "name", an exception is thrown.
#
#NOTE: This will "test"->("name") first and return it if it
#satisfies the 'statement'; i.e., the "variant" that this returns
#will just be the same name that was passed in if it satisfies the "test".
#If this is undesirable, then include the "name" within the "exclude" list.
#
#named options:
#   name => required, the original name
#   test => required, a coderef to test a name's validity, must return boolean
#       This receives the item as an argument and also as $_
#   max_length => required (in bytes)
#   exclude => optional, arrayref of names not to test
#
sub find_name_variant {
    my (%opts) = @_;

    die "Need “max_length”!" if !$opts{'max_length'};

    my $variant      = $opts{'name'};
    my $rename_index = 1;

    my %exclude;
    if ( $opts{'exclude'} ) {
        @exclude{ @{ $opts{'exclude'} } } = ();
    }

    my $test_cr = $opts{'test'};

    if ( length( $opts{'name'} ) > $opts{'max_length'} ) {
        die "Passed-in “name” ($opts{'name'}) is already longer than “max_length” ($opts{'max_length'})!";
    }

  NAME_ATTEMPT:
    while (1) {
        if ( !exists $exclude{$variant} ) {
            for ($variant) {
                last NAME_ATTEMPT if $test_cr->($_);
            }
        }

        $rename_index++;

        if ( length($rename_index) == length($variant) ) {
            die "The system failed to find a variant of “$opts{'name'}” that is no longer than $opts{'max_length'} bytes.";
        }

        $variant = $opts{'name'} . $rename_index;

        my $extra_chars = length($variant) - $opts{'max_length'};
        if ( $extra_chars > 0 ) {
            substr( $variant, 0 - length($rename_index) - $extra_chars, $extra_chars, q{} );
        }
    }

    return $variant;
}

1;
