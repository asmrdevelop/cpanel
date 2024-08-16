#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - scripts/safetybits.pl                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafetyBits ();

no warnings 'once';

*safe_chown     = *Cpanel::SafetyBits::safe_chown;
*safe_recchown  = *Cpanel::SafetyBits::safe_recchown;
*safe_lrecchown = *Cpanel::SafetyBits::safe_lrecchown;
*ishardlink     = *Cpanel::SafetyBits::ishardlink;
*safe_chmod     = *Cpanel::SafetyBits::safe_chmod;
*safe_recchmod  = *Cpanel::SafetyBits::safe_recchmod;
*setuids        = *Cpanel::SafetyBits::setuids;
*runasuser      = *Cpanel::SafetyBits::runasuser;

1;
