package Cpanel::TailWatch::RecentAuthedMailIpTracker::Config;

# cpanel - Cpanel/TailWatch/RecentAuthedMailIpTracker/Config.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Locale ();

our $VERSION = 0.1;

sub REQUIRED_ROLES {
    return [qw< MailReceive >];
}

my $locale;

sub is_managed_by_tailwatchd {
    return 1;
}

sub description {
    $locale ||= Cpanel::Locale->get_handle();
    return $locale->maketext("This driver keeps track of the IP addresses of recently authenticated IMAP and POP3 session.") . ' ' . $locale->maketext("This allows users with logins on the system to bypass delays and greylisting checks.");
}

1;
