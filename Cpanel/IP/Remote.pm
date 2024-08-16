package Cpanel::IP::Remote;

# cpanel - Cpanel/IP/Remote.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

sub get_current_remote_ip {
    Cpanel::LoadModule::load_perl_module('Cpanel::IP::TTY');
    my $tty_ip = Cpanel::IP::TTY::get_current_tty_ip_address();
    return $tty_ip if $tty_ip;

    return $ENV{'REMOTE_ADDR'} if $ENV{'REMOTE_ADDR'};

    return ( split( m{ }, $ENV{'SSH_CLIENT'} ) )[0] if $ENV{'SSH_CLIENT'};

    return ( split( m{ }, $ENV{'SSH_CONNECTION'} ) )[0] if $ENV{'SSH_CONNECTION'};

    return '';
}

1;
