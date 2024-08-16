package Cpanel::SSL::Auto::Check;

# cpanel - Cpanel/SSL/Auto/Check.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles ();

our $PID_FILE = '/var/cpanel/autossl_check.pid';

our $COMMAND = "$Cpanel::ConfigFiles::CPANEL_ROOT/bin/autossl_check";

sub generate_pidfile_for_username {
    my ($given_username) = @_;
    return ( $PID_FILE =~ s{\.pid$}{}r ) . "_" . $given_username . '.pid';
}

1;
