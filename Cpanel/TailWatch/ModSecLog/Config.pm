package Cpanel::TailWatch::ModSecLog::Config;

# cpanel - Cpanel/TailWatch/ModSecLog/Config.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Locale ();

our $VERSION = 0.1;

sub REQUIRED_ROLES {
    return [qw< WebServer >];
}

my $locale;

sub is_managed_by_tailwatchd {
    return 1;
}

sub description {
    $locale ||= Cpanel::Locale->get_handle();
    return $locale->maketext('Parses the [asis,ModSecurity] audit log and stores the events in the [asis,modsec] database for later viewing or analysis.');
}

1;
