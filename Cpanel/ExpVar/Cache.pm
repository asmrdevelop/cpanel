package Cpanel::ExpVar::Cache;

# cpanel - Cpanel/ExpVar/Cache.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# use warnings not enabled in this module to preserve original behavior before refactoring

our %VARCACHE = ();

sub has_expansion {
    return ( length $_[0]->{raw} && defined $VARCACHE{ $_[0]->{raw} } );
}

sub expand {
    return $VARCACHE{ $_[0]->{raw} } // $_[0]->{raw};
}

1;
