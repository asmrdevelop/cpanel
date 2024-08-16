package Cpanel::Config::DBOwners;

# cpanel - Cpanel/Config/DBOwners.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadConfig ();
use Cpanel::ConfigFiles        ();

sub load_user_to_dbowner {
    return _do_load();
}

sub load_dbowner_to_user {
    return _do_load( use_reverse => 1 );
}

sub _do_load {
    my %opts = @_;

    return scalar Cpanel::Config::LoadConfig::loadConfig(
        $Cpanel::ConfigFiles::DBOWNERS_FILE,
        undef,
        ': ',     # No need to match random spaces since we control the file
        undef,
        undef,    # reverse
        1,        # allow_undef_values since there will not be any
        \%opts,
    );
}

1;
