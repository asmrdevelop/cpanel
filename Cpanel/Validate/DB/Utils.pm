package Cpanel::Validate::DB::Utils;

# cpanel - Cpanel/Validate/DB/Utils.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub excess_statement {
    my ( $dbuser, $max ) = @_;

    my $excess = length($dbuser) - $max;
    if ( $excess > 0 ) {
        return locale()->maketext( '“[_1]” is too long by [quant,_2,character,characters].', $dbuser, $excess );
    }

    return;
}

my $locale;

sub locale {
    return $locale ||= do {
        require Cpanel::Locale;
        Cpanel::Locale->get_handle();
    };
}

1;
