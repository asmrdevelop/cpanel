#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/env.cgi                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

print "Content-type: text/plain\r\n\r\n";

foreach my $env ( sort keys %ENV ) {
    print "${env} = $ENV{$env}\n";
}
