package Cpanel::Security::Authn::TwoFactorAuth::Enabled;

# cpanel - Cpanel/Security/Authn/TwoFactorAuth/Enabled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadCpConf ();

our $is_enabled_cache;

sub is_enabled {
    return $is_enabled_cache if defined $is_enabled_cache;
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    $is_enabled_cache = exists $cpconf->{'SecurityPolicy::TwoFactorAuth'} ? $cpconf->{'SecurityPolicy::TwoFactorAuth'} : 0;
}

1;
