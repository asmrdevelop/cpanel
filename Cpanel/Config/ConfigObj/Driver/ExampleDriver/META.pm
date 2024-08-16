package Cpanel::Config::ConfigObj::Driver::ExampleDriver::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/ExampleDriver/META.pm
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

sub get_driver_name {
    return 'example_driver';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'www.cpanel.net',
        'name'   => {
            'short'  => 'Example Driver',
            'long'   => 'Example Driver for Developer Usage',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel® 11.32.4',
        'abstract' => "An example driver for developers to emulate.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} =
          $locale_handle->maketext("An example driver for developers to emulate.") . ' ' . $locale_handle->maketext( "Comes packed with meta examples that use cPanel’s localization system: [output,url,_1,Cpanel::Locale].", "https://go.cpanel.net/localedocs" ) . ' ' . $locale_handle->maketext('cPanel® does not translate strings. You will need to provide your own translations.');
    }

    return $content;
}

sub showcase {
    my $showcase = {
        'is_recommended'       => 0,
        'is_spotlight_feature' => 0,
    };
    return $showcase;
}
1;
