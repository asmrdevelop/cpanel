package Cpanel::Config::ConfigObj::Driver::UserDirProtect::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/UserDirProtect/META.pm
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
    return 'userdir_protect';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcaseuserdirprotect',
        'name'   => {
            'short'  => 'Apache: UserDir Protection',
            'long'   => 'Apache: UserDir Protection',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "This will configure Apache’s mod_userdir functionality to only be active on the default hostname. User site data will no longer be accessible under other usernames.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext("This will configure Apache’s mod_userdir functionality to only be active on the default hostname.") . ' ' . $locale_handle->maketext("User site data will no longer be accessible under other usernames.");
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
