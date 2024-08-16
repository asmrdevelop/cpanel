package Cpanel::Config::ConfigObj::Driver::WpToolkitACL::META;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);
our $VERSION = '1.0';
use Cpanel::LoadModule ();

use strict;

sub meta_version {
    return 1;
}

sub get_driver_name {
    return 'WpToolkitACL_driver';
}

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'Plesk',
        'url'    => 'plesk.com',
        'name'   => {
            'short'  => 'WP Toolkit ACL driver',
            'long'   => 'WP Toolkit ACL driver',
            'driver' => get_driver_name(),
        },
        'abstract' => "WP Toolkit ACL driver",
        'version'  => $Cpanel::Config::ConfigObj::Driver::WpToolkitACL::VERSION,
        'readonly' => 1,
        'auto_enable' => 1
    };

    return $content;
}

sub showcase {
    return -1;
}

1;
