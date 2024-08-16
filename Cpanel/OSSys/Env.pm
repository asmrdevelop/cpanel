package Cpanel::OSSys::Env;

# cpanel - Cpanel/OSSys/Env.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = 1.0;

# issafe Cpanel::Branding::Lite::_loadenvtype version uses global cache
sub get_envtype {
    my ($envtype);
    if ( open( my $env_fh, '<', '/var/cpanel/envtype' ) ) {
        $envtype = readline($env_fh);
        close($env_fh);
        chomp($envtype);
    }
    return $envtype || 'standard';
}

1;
