package Cpanel::EtcCpanel;

# cpanel - Cpanel/EtcCpanel.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

# This package has functionality to create /etc/cpanel directory. It may be used in future to add any utility functions
# related to /etc/cpanel directory.

use strict;
use Umask::Local();

our $ETC_CPANEL_DIR = "/etc/cpanel";

# This function creates /etc/cpanel directory with the right
# permissions (0755) if it's not already created.
# Features like EA4 and IPV6 are using this folder.
sub make_etc_cpanel_dir {
    unless ( -d $ETC_CPANEL_DIR ) {

        # Change the umask for creating the /etc/cpanel/ directory with 755 permissions.
        my $umask = Umask::Local->new(022);
        unless ( mkdir $ETC_CPANEL_DIR ) {
            return ( 0, "$!" );
        }
    }
    return 1;
}

1;
