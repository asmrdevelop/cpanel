package Cpanel::Validate::NameServer;

# cpanel - Cpanel/Validate/NameServer.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::Domain::Tiny ();
use Cpanel::StringFunc::Case       ();
use Cpanel::StringFunc::Trim       ();
use Cpanel::Validate::IP           ();

sub is_valid {
    my ($ns) = @_;
    return 1 if Cpanel::Validate::IP::is_valid_ip($ns);
    return 1 if Cpanel::Validate::Domain::Tiny::validdomainname($ns);
    return;
}

sub normalize {
    my ($ns) = @_;
    $ns = Cpanel::StringFunc::Trim::ws_trim($ns);
    $ns = Cpanel::StringFunc::Case::ToLower($ns);
    return $ns;
}

1;
