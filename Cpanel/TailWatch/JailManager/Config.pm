package Cpanel::TailWatch::JailManager::Config;

# cpanel - Cpanel/TailWatch/JailManager/Config.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

our $VERSION = 0.1;

sub REQUIRED_ROLES {
    return [qw< WebServer >];
}

my $locale;

sub is_managed_by_tailwatchd {
    return 0;
}

sub description {
    require Cpanel::Locale;    # This is not compiled so require
    $locale ||= Cpanel::Locale->get_handle();

    my $desc = $locale->maketext(
        'Manages Jails used for the “[_1]”.',
        'EXPERIMENTAL: Jail Apache Virtual Hosts using mod_ruid2 and cPanel® jailshell',    # Tweak Setting labels are not translated
    );
    $desc .= ' ';
    $desc .= $locale->maketext(
        'This option is managed by “[_1]”, and should be enabled or disabled there.',
        $locale->maketext('Tweak Settings'),
    );
    return $desc;
}

sub is_enabled {
    my ( $my_ns, $tailwatch_obj ) = @_;

    return 0 if !$tailwatch_obj->{'global_share'}->{'data_cache'}{'cpconf'}->{'jailapache'};
    return 1;
}

1;
