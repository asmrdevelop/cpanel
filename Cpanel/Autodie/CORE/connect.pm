package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/connect.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 connect( SOCKET, NAME )

As described in L<perlfunc/connect>.

=cut

sub connect {
    my ( $socket, $name ) = @_;

    local ( $!, $^E );
    return CORE::connect( $socket, $name ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::SocketConnectError', [ error => $err, to => $name ] );
    };
}

1;
