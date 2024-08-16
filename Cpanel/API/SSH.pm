package Cpanel::API::SSH;

# cpanel - Cpanel/API/SSH.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not fully vetted for warnings

use Cpanel::SSH::Port ();

sub get_port {
    ## no args
    my ( $args, $result ) = @_;
    my $data = Cpanel::SSH::Port::getport();
    $result->data( { port => $data } );
    return 1;
}

our %API = (
    get_port => { allow_demo => 1 },
);

1;
