package Cpanel::RestartSrv::Initd;

# cpanel - Cpanel/RestartSrv/Initd.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::FilesystemNodeName ();

our $INIT_D_DIR = '/etc/init.d';

sub has_service_via_initd {
    my $p_service = shift;

    # protect against values not being passed in #
    return 0 if !$p_service;

    # sanity check and then compute init script name #
    Cpanel::Validate::FilesystemNodeName::validate_or_die($p_service);
    my $init_script = "$INIT_D_DIR/$p_service";

    # unknown service
    return 0 if !-f $init_script || !-x _;

    return 1;
}

1;
