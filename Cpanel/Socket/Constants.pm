package Cpanel::Socket::Constants;

# cpanel - Cpanel/Socket/Constants.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $SO_REUSEADDR = 2;

our $AF_UNIX  = 1;
our $AF_INET  = 2;
our $PF_INET  = 2;
our $AF_INET6 = 10;
our $PF_INET6 = 10;

#NB: In Socket.pm these are IPPROTO_IP, etc.
our $PROTO_IP   = 0;
our $PROTO_ICMP = 1;
our $PROTO_TCP  = 6;
our $PROTO_UDP  = 17;

our $IPPROTO_TCP;
*IPPROTO_TCP = \$PROTO_TCP;

our $SO_PEERCRED   = 17;
our $SOL_SOCKET    = 1;
our $SOCK_STREAM   = 1;
our $SOCK_NONBLOCK = 2048;

our $SHUT_RD   = 0;
our $SHUT_WR   = 1;
our $SHUT_RDWR = 2;

our $MSG_PEEK     = 2;
our $MSG_NOSIGNAL = 16384;

1;
