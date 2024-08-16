package Whostmgr::Bandwidth::Tiny;

# cpanel - Whostmgr/Bandwidth/Tiny.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Userdomains        ();
use Cpanel::Config::LoadConfig ();

sub loaduserbwlimits {
    my $conf_ref = shift;
    my $reverse  = shift;
    my $simple   = shift;

    if ( !-e '/etc/userbwlimits' ) { Cpanel::Userdomains::updateuserdomains(); }

    $conf_ref = Cpanel::Config::LoadConfig::loadConfig(
        '/etc/userbwlimits',
        $conf_ref,
        '\s*[:]\s*',
        '^\s*[#]',
        0, 0,
        {
            'use_reverse'          => $reverse ? 0 : 1,
            'use_hash_of_arr_refs' => $simple  ? 0 : 1,
        }
    );
    if ( !defined($conf_ref) ) {
        $conf_ref = {};
    }
    return wantarray ? %{$conf_ref} : $conf_ref;
}

1;
