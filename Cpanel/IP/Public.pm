package Cpanel::IP::Public;

# cpanel - Cpanel/IP/Public.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Sources ();
use Cpanel::HTTP::Client    ();
use Cpanel::Logger          ();

#overridden in tests
*_SANDBOX_ENDPOINT = \&Cpanel::Config::Sources::MY_IPV4_ENDPOINT;
*_is_sandbox       = \&Cpanel::Logger::is_sandbox;

sub get_public_ipv4 {
    my $http = Cpanel::HTTP::Client->new()->die_on_http_error();

    my $url =
        _is_sandbox()
      ? _SANDBOX_ENDPOINT()
      : Cpanel::Config::Sources::loadcpsources()->{'MYIP'};

    return $http->get($url)->content() =~ s<\s\z><>r;
}

1;
