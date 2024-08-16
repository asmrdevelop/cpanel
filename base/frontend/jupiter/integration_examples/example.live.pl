#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/frontend/jupiter/integration_examples/example.live.pl
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LiveAPI ();

my $cpanel = Cpanel::LiveAPI->new();

print "Content-type: text/html\r\n\r\n";

print $cpanel->header('Example perl Page');

print "We recommend that you create a new template toolkit file and place it in the jupiter theme's root directory.";

print $cpanel->footer();

$cpanel->end();
