package Cpanel::Config::ConfigObj::Driver::Resetpass::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/Resetpass/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
our $VERSION = 1.1;

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'resetpass';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/resetpassdocs',
        'name'   => {
            'short'  => 'cPanel Reset Password',
            'long'   => 'Reset Password for cPanel accounts',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel® 56.0',
        'abstract' => "This feature allows cPanel account users to reset their passwords.",
        'version'  => $VERSION
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext("This feature allows [asis,cPanel] account users to reset their passwords.");
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
