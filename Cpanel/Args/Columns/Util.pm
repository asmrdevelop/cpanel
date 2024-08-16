package Cpanel::Args::Columns::Util;

# cpanel - Cpanel/Args/Columns/Util.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

#
#Expects:
#   - $white_list_keys  Array ref of keys to keep
#   - $records_ar       Array ref of hashes usually from an API call
#   - $message_sr       Scalar ref of message so we can report if any columns were unused
#   - $invalid_columns_ar Array ref of invalid columns we populate and pass back to caller if exists
#
#Returns:
#   - 1
#   - Also modifies $records to remove all keys that do not match a value found in $white_list_keys
#
#Note:
#   Will not fail if you pass invalid columns
sub apply {

    my ( $white_list_keys, $records_ar, $message_sr, $invalid_columns_ar ) = @_;

    #Will only work on homogeneous data - if hash changes by index this will not provide consistent results
    my @keys_to_delete = ();

    #Create a hash so it's a O(1) lookup.  The tradeoff is speed vs memory since we would have to loop an array on array vs an array on hash.
    #  Either is negligible because both array and hash should be small.
    my %white_list_hash      = map { $_ => 1 } @$white_list_keys;
    my $single_record_hash   = $records_ar->[0];
    my @keys_that_dont_match = grep { !exists $single_record_hash->{$_} } @$white_list_keys;

    @keys_to_delete = grep { !exists $white_list_hash{$_} } keys %{ $records_ar->[0] };

    if ( scalar @keys_that_dont_match ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
        $$message_sr = Cpanel::Locale->get_handle()->maketext(
            '[list_and_quoted,_1] [numerate,_2,is not a,are not] valid [numerate,_2,column,columns].',
            \@keys_that_dont_match,
            scalar @keys_that_dont_match
        );
        @$invalid_columns_ar = @keys_that_dont_match;
    }

    foreach my $record (@$records_ar) {
        delete @{$record}{@keys_to_delete};
    }

    return 1;
}

1;
