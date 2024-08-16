package Cpanel::Socket::IP;

# cpanel - Cpanel/Socket/IP.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Socket::IP - IO::Socket::IP with an exception-throwing C<new()>

=head1 SYNOPSIS

    #This will die() on failure.
    my $socket = Cpanel::Socket::IP->new(...);

See L<IO::Socket::IP> for the arguments that C<new()> expects.

=cut

use parent (
    'Cpanel::Socket::IOBase',
    'IO::Socket::IP',
);

use constant _IO_SUPERCLASS => 'IO::Socket::IP';

1;
