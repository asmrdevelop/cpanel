package Cpanel::Hulk::Constants;

# cpanel - Cpanel/Hulk/Constants.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# This module must not import Errno of have external deps
# as it is used in exim

use Cpanel::Fcntl::Constants  ();
use Cpanel::Socket::Constants ();

*F_GETFL    = \$Cpanel::Fcntl::Constants::F_GETFL;
*F_SETFL    = \$Cpanel::Fcntl::Constants::F_SETFL;
*O_NONBLOCK = \$Cpanel::Fcntl::Constants::O_NONBLOCK;

our $EINTR       = 4;
our $EPIPE       = 32;
our $EINPROGRESS = 115;
our $ETIMEDOUT   = 110;
our $EISCONN     = 106;
our $ECONNRESET  = 104;
our $EAGAIN      = 11;

*PROTO_IP   = \$Cpanel::Socket::Constants::PROTO_IP;
*PROTO_ICMP = \$Cpanel::Socket::Constants::PROTO_ICMP;
*PROTO_TCP  = \$Cpanel::Socket::Constants::PROTO_TCP;

*SO_PEERCRED = \$Cpanel::Socket::Constants::SO_PEERCRED;
*SOL_SOCKET  = \$Cpanel::Socket::Constants::SOL_SOCKET;
*SOCK_STREAM = \$Cpanel::Socket::Constants::SOCK_STREAM;

*AF_INET6 = \$Cpanel::Socket::Constants::AF_INET6;
*AF_INET  = \$Cpanel::Socket::Constants::AF_INET;
*AF_UNIX  = \$Cpanel::Socket::Constants::AF_UNIX;

our $TOKEN_SALT_BASE = '$6$';
our $SALT_LENGTH     = 16;

# TIME_BASE - The first allowed time for a login (Sat Sep  6 05:40:00 2014 CDT)
# We subtract this from the timestamp to give us the most randomness possible
# for the salt.
our $TIME_BASE            = 1410000000;
our $SIX_HOURS_IN_SECONDS = 21600;
1;
