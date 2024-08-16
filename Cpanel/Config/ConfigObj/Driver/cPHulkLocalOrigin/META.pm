package Cpanel::Config::ConfigObj::Driver::cPHulkLocalOrigin::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/cPHulkLocalOrigin/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = '1.1';

sub meta_version {
    return 1;
}

# Avoids having to deal with locale information
# when all we care about is the driver name.
sub get_driver_name {
    return 'cPHulk_Local_Origin';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcasecPHulkLocalOrigin',
        'name'   => {
            'short'  => 'cPHulk: Username-based Protection for local requests',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "Limit username-based protection to trigger only on requests originating from the local system. This ensures that a user cannot brute force other accounts on the same server.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('[asis,cPHulk]: Username-based Protection for local requests');
        $content->{'abstract'} = $locale_handle->maketext("Limit username-based protection to trigger only on requests originating from the local system. This ensures that a user cannot brute force other accounts on the same server.");
    }

    $content->{'name'}->{'long'} = $content->{'name'}->{'short'};

    return $content;
}

sub showcase {
    return 0;
}

sub auto_enable {
    return 1;
}

1;
