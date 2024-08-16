package Whostmgr::AcctInfo::Plans;

# cpanel - Whostmgr/AcctInfo/Plans.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();

our $USERPLANS_FILE = '/etc/userplans';

sub loaduserplans {
    my $userplans = loaduserplans_include_undefined();
    delete @{$userplans}{ grep { $userplans->{$_} eq 'undefined' } keys %{$userplans} };
    return $userplans;
}

sub loaduserplans_include_undefined {
    return Cpanel::Config::LoadConfig::loadConfig( $USERPLANS_FILE, -1, ': ' );
}

1;
