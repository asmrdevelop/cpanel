package Cpanel::YAML::Syck;

# cpanel - Cpanel/YAML/Syck.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# Because so many things load YAML::Syck, it's not safe to enforce strict or warnings here.
##no critic qw(RequireUseStrict)

use YAML::Syck ();

sub _init {
    $YAML::Syck::LoadBlessed = 0;
    {
        no warnings 'redefine';
        *Cpanel::YAML::Syck::_init = sub { };
    }
    return;
}

_init();

1;
