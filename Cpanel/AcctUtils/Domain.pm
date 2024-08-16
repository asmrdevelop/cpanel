package Cpanel::AcctUtils::Domain;

# cpanel - Cpanel/AcctUtils/Domain.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::HasCpUserFile  ();

sub getdomain {
    my ($user) = @_;
    return unless Cpanel::Config::HasCpUserFile::has_cpuser_file($user);
    return Cpanel::Config::LoadCpUserFile::loadcpuserfile($user)->{'DOMAIN'};
}

1;
