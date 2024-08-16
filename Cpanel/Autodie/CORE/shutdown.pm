package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/shutdown.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant _ENOTCONN => 107;

=head1 FUNCTIONS

=head2 shutdown()

cf. L<perlfunc/shutdown>

=cut

sub shutdown {
    my ( $socket, $how ) = @_;

    local ( $!, $^E );
    return CORE::shutdown( $socket, $how ) || _die_shutdown($how);
}

=head2 shutdown_if_connected()

Like C<shutdown()> but returns undef on ENOTCONN rather than
throwing an exception.

=cut

sub shutdown_if_connected {
    my ( $socket, $how ) = @_;

    local ( $!, $^E );
    return CORE::shutdown( $socket, $how ) || do {
        _die_shutdown($how) if $! != _ENOTCONN();
        return 0;
    };
}

sub _die_shutdown {
    my ($how) = @_;

    my $err = $!;

    local $@;
    require Cpanel::Exception;

    die Cpanel::Exception::create( 'IO::SocketShutdownError', [ error => $err, how => $how ] );
}

1;
