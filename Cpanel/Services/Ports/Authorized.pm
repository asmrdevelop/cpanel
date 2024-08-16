package Cpanel::Services::Ports::Authorized;

# cpanel - Cpanel/Services/Ports/Authorized.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)

use Cpanel::DAV::Ports      ();
use Cpanel::Services::Ports ();

sub allowed_tcp_ports {
    my @ports = sort { $a <=> $b } (
        $Cpanel::Services::Ports::SERVICE{'cpanel'},
        $Cpanel::Services::Ports::SERVICE{'cpanels'},
        $Cpanel::Services::Ports::SERVICE{'webmail'},
        $Cpanel::Services::Ports::SERVICE{'webmails'},
        $Cpanel::Services::Ports::SERVICE{'whostmgr'},
        $Cpanel::Services::Ports::SERVICE{'whostmgrs'},

        values( %{ Cpanel::DAV::Ports::get_ports() } ),

        (
            21,      #ftp
            22,      #ssh
            25,      #smtp
            26,      #alternate smtp
            53,      #dns
            80,      #http
            110,     #pop3
            143,     #imap
            443,     #https
            465,     #smtps
            587,     #mail MSA
            993,     #imaps
            995,     #pop3s
            3306,    #mysql
            8080,    #http, testing
            8443,    #https, testing

            #cphulkd opens this for local services. We don’t actually need to
            #open it to the outside world, but since we know we only bind to
            #127.0.0.1 it should be fine. It’s simple enough just to add an
            #iptables rule for pre-CentOS 7, but firewalld (used in CentOS 7)
            #makes it more awkward.
            579,
        ),
    );

    # Order is important and strings don't do well in numeric sorts.
    push @ports, '49152:65534';

    return @ports;
}

sub allowed_udp_ports {
    return (53);
}

sub allowed_ports_by_protocol {
    return {
        tcp => [ allowed_tcp_ports() ],
        udp => [ allowed_udp_ports() ],
    };
}

1;
