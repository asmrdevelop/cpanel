package Cpanel::Form::Utils;

# cpanel - Cpanel/Form/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();

#This returns the given @keys to be in the order in which Cpanel::Form
#stores keys with the same name.
#
#This is useful, e.g., for rebuilding a form submission when there
#were multiple keys given with the same name, and we need to be sure
#to process those values in the given order.
#
sub restore_same_name_keys_order {
    my (@keys) = @_;

    Cpanel::Context::must_be_list();

    my ( $a_str, $a_num, $b_str, $b_num );

    my @sorted = sort {
        return 0 if !( $a cmp $b );

        ( $a_str, $a_num ) = ( $a =~ m<(.*)-(.*)> );
        if ( length($a_num) && !( $a_num =~ tr<0-9><>c ) ) {
            ( $b_str, $b_num ) = ( $b =~ m<(.*)-(.*)> );

            if ( length($b_num) && !( $b_num =~ tr<0-9><>c ) ) {
                if ( $a_str eq $b_str ) {
                    return ( $a_num <=> $b_num );
                }
            }
        }

        return ( $a cmp $b );
    } @keys;

    return @sorted;
}

1;
