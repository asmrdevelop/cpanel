package Cpanel::Branding::Lite::Config;

# cpanel - Cpanel/Branding/Lite/Config.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin::Serializer ();

my $theme_config_defaults = {
    'icon' => {
        'format' => 'jpg',
        'width'  => '32',
        'height' => '32',
    },
};

sub load_theme_config_from_file {
    my ($file) = @_;

    if ( length $file && -e $file ) {
        my $config;
        eval { $config = Cpanel::AdminBin::Serializer::LoadFile($file); };
        if ($@) {
            print STDERR "Could not load theme config: $@\n";
        }
        return $config;
    }

    return $theme_config_defaults;
}
1;
