package Cpanel::Config::ConfigObj::Driver::cPanelID::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/cPanelID/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

use Try::Tiny;

use Cpanel::LoadModule ();

our $VERSION = '1.1';

sub meta_version {
    return 1;
}

# Avoids having to deal with locale information
# when all we care about is the driver name.
sub get_driver_name {
    return 'cpanel_id';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, L.L.C.',
        'url'    => 'https://go.cpanel.net/featureshowcasecPanelID',
        'name'   => {
            'short'  => 'cPanelID',
            'driver' => get_driver_name(),
        },
        'since'    => '',
        'abstract' => "cPanelID provides you with the ability to log in to cPanel with your cPanel ID account. This feature allows you to use a single account to login to all of your cPanel accounts. In the future, this feature will allow cPanel, Inc. to provide faster support.",
        'version'  => $VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} = join(
            ' ', $locale_handle->maketext("[asis,cPanelID] provides you with the ability to log in to [asis,cPanel] with your [asis,cPanelID] account."),
            $locale_handle->maketext("This feature allows you to use a single account to log in to all of your cPanel accounts."),
            $locale_handle->maketext("In the future, this feature will allow [asis,cPanel, L.L.C.] to provide faster support.")
        );
    }

    $content->{'name'}->{'long'} = $content->{'name'}->{'short'};

    return $content;
}

sub showcase {
    return 0;
}

sub auto_enable {
    Cpanel::LoadModule::load_perl_module('Cpanel::LicenseAuthn');

    # Do not auto_enable unless available
    my ( $id, $secret ) = Cpanel::LicenseAuthn::get_id_and_secret('featureshowcase');

    return 0 if !$id;

    return 1;
}

1;
