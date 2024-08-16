package Cpanel::DB::Prefix::Conf;

# cpanel - Cpanel/DB/Prefix/Conf.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::LoadCpConf ();

our $use_prefix;    # our for testing purposes

sub use_prefix {
    return $use_prefix if defined $use_prefix;
    my $cpanel_conf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $use_prefix = $cpanel_conf->{'database_prefix'};
}

1;
