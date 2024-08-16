package Cpanel::Locale::Utils::SpecialCase;

# cpanel - Cpanel/Locale/Utils/SpecialCase.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
#### WARNING!
#
# This module is for use only in exceptional circumstances.
# Before using anything in here, please verify with at least one other
# developer that your work needs to use this code.

use Cpanel::HTTP   ();
use Cpanel::Locale ();

sub get_unauthenticated_user_handle {
    my @preferred = @_;

    local $ENV{'CPANEL'};

    #We treat en-us and en as the same locale, so normalize the
    #browser's request.
    my @locales = map { my $lc = lc($_); $lc eq 'en-us' ? 'en' : $lc } Cpanel::HTTP::get_requested_locales();
    return Cpanel::Locale->get_handle( @preferred, @locales );
}

1;
