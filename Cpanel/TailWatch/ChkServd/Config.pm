package Cpanel::TailWatch::ChkServd::Config;

# cpanel - Cpanel/TailWatch/ChkServd/Config.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::Locale ();

our $VERSION = 0.1;

my $locale;

sub available_for_dnsonly {
    return 1;
}

sub is_managed_by_tailwatchd {
    return 1;
}

sub description {
    $locale ||= Cpanel::Locale->get_handle();
    return $locale->maketext("Responsible for checking, monitoring and restarting services.");
}

1;
