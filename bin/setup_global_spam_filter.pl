#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - bin/setup_global_spam_filter.pl         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Logger ();

my $replacement = '/usr/local/cpanel/bin/setup_global_spam_filter';
my $logger      = Cpanel::Logger->new;
$logger->deprecated("This script is deprecated and will be removed in version 72.  Call $replacement instead.");
exec $replacement, @ARGV;
exit 255;
