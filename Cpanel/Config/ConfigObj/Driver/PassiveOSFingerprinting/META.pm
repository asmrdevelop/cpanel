package Cpanel::Config::ConfigObj::Driver::PassiveOSFingerprinting::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/PassiveOSFingerprinting/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = 1.1;

sub meta_version {
    return 1;
}

# Avoids having to deal with locale information
# when all we care about is the driver name.
sub get_driver_name {
    return 'passive_os_fingerprinting';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcasePassiveOSFingerprinting',
        'name'   => {
            'short'  => 'Passive OS Fingerprinting',
            'long'   => 'Passive OS Fingerprinting',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "Passive OS Fingerprinting adds additional information to login and brute force notifications, such as the HTTP client version, link type, operating system, and the remote system’s language settings.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('Passive OS Fingerprinting');
        $content->{'name'}->{'long'}  = $content->{'name'}->{'short'};
        $content->{'abstract'}        = $locale_handle->maketext("Passive OS Fingerprinting adds additional information to login and brute force notifications, such as the HTTP client version, link type, operating system, and the remote system’s language settings.");
    }

    return $content;
}

sub showcase {
    return 0;
}

sub auto_enable {
    return 1;
}

1;
