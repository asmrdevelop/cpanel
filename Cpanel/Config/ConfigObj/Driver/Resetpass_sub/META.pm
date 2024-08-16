package Cpanel::Config::ConfigObj::Driver::Resetpass_sub::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/Resetpass_sub/META.pm
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
    return 'resetpass_sub';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/resetsubaccountpass',
        'name'   => {
            'short'  => 'cPanel Subaccount Reset Password',
            'long'   => 'Reset Password for cPanel subaccounts',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel® 56.0',
        'abstract' => 'This feature allows cPanel Subaccount users with access to email, FTP, and Web Disk services to reset their passwords.',
        'version'  => $VERSION
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext('This feature allows [asis,cPanel] [asis,Subaccount] users with access to email, FTP, and [asis,Web Disk] services to reset their passwords.');
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
