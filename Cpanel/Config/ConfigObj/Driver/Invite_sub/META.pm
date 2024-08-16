package Cpanel::Config::ConfigObj::Driver::Invite_sub::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/Invite_sub/META.pm
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
    return 'invite_sub';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/invitesubaccount',
        'name'   => {
            'short'  => 'Subaccount Invites',
            'long'   => 'Account Invites for Subaccounts',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel® 60.0',
        'abstract' => 'The Subaccount Invites feature allows new Subaccount users to set their own passwords. The feature sends a welcome email, which prompts the user to click a link in order to complete the initial setup of their account.',
        'version'  => $VERSION
    };
    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext('The [asis,Subaccount Invites] feature allows new [asis,Subaccount] users to set their own passwords. The feature sends a welcome email, which prompts the user to click a link in order to complete the initial setup of their account.');
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
