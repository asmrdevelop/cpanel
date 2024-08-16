package Cpanel::SafeRun::Errors;

# cpanel - Cpanel/SafeRun/Errors.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# *** DO NOT ADD ANY DEPS HERE ***
use Cpanel::SafeRun::Simple ();

# *** DO NOT ADD ANY DEPS HERE ***

sub saferunallerrors {
    my $output_ref = Cpanel::SafeRun::Simple::_saferun_r( \@_, 1 );    #1 = errors to stdout
    return wantarray ? split( /\n/, $$output_ref ) : $$output_ref;
}

sub saferunnoerror {
    my $output_ref = Cpanel::SafeRun::Simple::_saferun_r( \@_, 2 );    # 2 = errors to devnull
    return wantarray ? split( /\n/, $$output_ref ) : $$output_ref;
}

sub saferunonlyerrors {
    my $output_ref = Cpanel::SafeRun::Simple::_saferun_r( \@_, 3 );
    return wantarray ? split( /\n/, $$output_ref ) : $$output_ref;
}

1;
