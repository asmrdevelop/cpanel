package Cpanel::Validate::DUNS;

# cpanel - Cpanel/Validate/DUNS.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::Regex     ();

sub or_die {
    my ($copy) = @_;

    $copy =~ m<\A$Cpanel::Regex::regex{'DUNS'}\z> or do {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid Dun [output,amp] Bradstreet [output,acronym,D-U-N-S,Data Universal Numbering System] number.', [$copy] );
    };

    return;
}

1;
