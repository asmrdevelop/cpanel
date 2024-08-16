package Cpanel::FtpUtils::Config::Proftpd::CfgFile;

# cpanel - Cpanel/FtpUtils/Config/Proftpd/CfgFile.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub bare_find_conf_file {
    my $conf = '/etc/proftpd.conf';

    if ( !-e $conf ) {
        $conf = '/usr/local/etc/proftpd.conf' if ( -e '/usr/local/etc/proftpd.conf' );
    }

    return $conf;
}
1;
