package Cpanel::Autodie::Socket;

# cpanel - Cpanel/Autodie/Socket.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Autodie::Socket

=head1 SYNOPSIS

    Cpanel::Autodie::Socket::socket( … );
    Cpanel::Autodie::Socket::connect( … );
    Cpanel::Autodie::Socket::shutdown( … );

    #Convenience/speed, to avoid a throwaway exception:
    my $was_connected = Cpanel::Autodie::Socket::shutdown_if_connected( … );

=head1 DESCRIPTION

These functions mostly wrap Perl’s built-ins for socket handling.
Like other functions in this namespace, this is basically “autodie::Lite”,
with L<Cpanel::Exception> subclasses thrown rather than L<autodie>’s
exceptions.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Autodie ( 'socket', 'connect', 'shutdown', 'shutdown_if_connected' );

*socket                = *Cpanel::Autodie::socket;
*connect               = *Cpanel::Autodie::connect;
*shutdown              = *Cpanel::Autodie::shutdown;
*shutdown_if_connected = *Cpanel::Autodie::shutdown_if_connected;

1;
