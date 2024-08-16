package Cpanel::Exim::Config::Ports;

# cpanel - Cpanel/Exim/Config/Ports.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

our %TLS_ON_CONNECT_PORTS = ( '465' => 1 );
our %LISTEN_PORTS         = ( '25'  => 1, '465' => 1, '587' => 1 );

1;
