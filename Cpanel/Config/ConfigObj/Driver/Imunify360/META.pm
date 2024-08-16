package Cpanel::Config::ConfigObj::Driver::Imunify360::META;

if( -e '/usr/local/cpanel/Cpanel/Config/ConfigObj/Interface/Config/Version') {
    eval('use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);');
}

our $VERSION = '1.0';
use Cpanel::LoadModule ();

use strict;

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'Imunify360_driver';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'CloudLinux Zug GmbH',
        'url'    => 'imunify360.com',
        'name'   => {
            'short'  => 'Imunify360 Driver',
            'long'   => 'Driver for Imunify360 Plugin',
            'driver' => get_driver_name(),
        },
        'since'    => 'cPanel & WHM version 11.32.4',
        'abstract' => "Imunify360 Driver",
        'version'  => $Cpanel::Config::ConfigObj::Driver::LveManager::VERSION,
    };

    if ($locale_handle) {
        $content->{'abstract'} = $locale_handle->maketext("Imunify360 driver.");
    }

    return $content;
}

1;
