package Cpanel::URI::Escape::Fast;

# cpanel - Cpanel/URI/Escape/Fast.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

###### DO NOT USE THIS MODULE DIRECTLY.  PLEASE CALL Cpanel::Encoder::URI instead ######

my %escapes;

BEGIN {
    # No need to have escapes for characters we will not escape
    %escapes = map { chr($_) => sprintf( '%%%02x', $_ ) } ( 0 .. 47, 58 .. 64, 91 .. 94, 96, 123 .. 255 );
}

# light version of Cpanel::URI::Escape::Fast::uri_escape
sub uri_escape {
    return defined $_[0] && $_[0] =~ tr{A-Za-z0-9_.~-}{}c ? ( $_[0] =~ s/([^A-Za-z0-9\-_\.~])/$escapes{$1}/gr ) : $_[0];
}

1;
