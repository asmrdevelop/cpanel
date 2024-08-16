package Cpanel::Socket::UNIX;

# cpanel - Cpanel/Socket/UNIX.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Socket::UNIX - IO::Socket::UNIX with an exception-throwing C<new()>

=head1 SYNOPSIS

    #This will die() on failure.
    my $socket = Cpanel::Socket::UNIX->new(...);

See L<IO::Socket::UNIX> for the arguments that C<new()> expects.

=cut

use parent (
    'Cpanel::Socket::IOBase',
    'IO::Socket::UNIX',
);

use constant _IO_SUPERCLASS => 'IO::Socket::UNIX';

1;
