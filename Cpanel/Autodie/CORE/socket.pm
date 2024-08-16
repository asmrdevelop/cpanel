package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/socket.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 socket( SOCKET, DOMAIN, TYPE, PROTOCOL )

cf L<perlfunc/socket>

=cut

# $_[0]: socket
sub socket {
    my ( $domain, $type, $protocol ) = ( @_[ 1 .. 3 ] );

    local ( $!, $^E );
    return CORE::socket( $_[0], $domain, $type, $protocol ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::SocketOpenError', [ domain => $domain, type => $type, protocol => $protocol, error => $err ] );
    };
}

1;
