package Cpanel::TailWatch::Utils::Stubs::ScalarUtil;

# cpanel - Cpanel/TailWatch/Utils/Stubs/ScalarUtil.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=pod

    The goal of this module is to avoid loading Scalar::Util at runtime.

    The weaken function is the only one used at this time.
    This package provides an empty 'weaken' function
    in order to avoid to die when called.

=cut

BEGIN {
    if ( 'Scalar::Util'->can('weaken') ) {
        warn "Can't stub Scalar::Util: the module is already loaded!";
    }
    else {
        # block Scalar::Util but provide an empty weaken function if used
        *Scalar::Util::weaken = sub { };
        $INC{'Scalar/Util.pm'} = __FILE__;    ## no critic(Variables::RequireLocalizedPunctuationVars) - we want to fake Scalar::Util being loaded
    }
}

1;
