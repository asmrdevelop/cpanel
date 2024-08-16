package Cpanel::Config::Users;

# cpanel - Cpanel/Config/Users.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Config::LoadUserDomains ();

our $VERSION = '1.1';

sub getcpusers {
    my $trueuserdomains_ref = Cpanel::Config::LoadUserDomains::loadtrueuserdomains( undef, 1 );
    return wantarray ? keys %$trueuserdomains_ref : [ keys %$trueuserdomains_ref ];
}

1;
