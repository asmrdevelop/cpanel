package Cpanel::TailWatch::MailHealth::Config;

# cpanel - Cpanel/TailWatch/MailHealth/Config.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;
use Cpanel::Locale ();

our $VERSION = 0.1;

sub REQUIRED_ROLES {
    return [qw< MailReceive MailSend >];
}

my $locale;

sub is_managed_by_tailwatchd {
    return 1;
}

sub description {
    $locale ||= Cpanel::Locale->get_handle();
    return $locale->maketext("This driver monitors the mail log for problems with mail services.");
}

1;
