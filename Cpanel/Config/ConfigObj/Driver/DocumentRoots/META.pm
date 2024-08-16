package Cpanel::Config::ConfigObj::Driver::DocumentRoots::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/DocumentRoots/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = 1.0;

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'document_roots';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => '',
        'name'   => {
            'short'  => 'Make document roots in the public_html directory?',
            'long'   => 'Configurable DocumentRoots',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "In older versions of cPanel &amp; WHM the Addon and Sub Domain creation interfaces suggested '~/public_html' as the document root of the new domain. Beginning with version 58 you can choose to have the suggested document root be the account’s home directory, or the traditional '~/public_html' location.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} =
          $locale_handle->maketext(
            "In older versions of [asis, cPanel amp() WHM] the Addon and Sub Domain creation interfaces suggested a directory within [asis,~/public_html] as the document root of the new domain (e.g. [asis,~/public_html/example.com]). Beginning with version 58 you can choose to have the suggested document root be within the account’s home directory (e.g. [asis,~/example.com]), or within the traditional [asis,~/public_html] location. [output,strong,Note: Enabling this setting restricts Addon and Sub Domain document roots to the public_html directory.]"
          );
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
