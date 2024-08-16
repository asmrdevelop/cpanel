package Cpanel::AdminBin::Utils::Exit;

# cpanel - Cpanel/AdminBin/Utils/Exit.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# This code is not in Cpanel::AdminBin::Utils in order to avoid loading
# it in Cpanel::AdminBin::Server as this module will be in memory all the
# time.

sub exit_msg {
    my ( $child_status, $call_ref ) = @_;

    require Cpanel::ChildErrorStringifier;
    my $msg_items_all = Cpanel::ChildErrorStringifier->new($child_status)->terse_autopsy();

    my $key = join( '/', @{$call_ref}{ 'namespace', 'module', 'function' } );
    return "adminbin $key: $msg_items_all";
}

1;
