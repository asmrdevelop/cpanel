package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/socketpair.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=head1 FUNCTIONS

=head2 socketpair( SOCKET1, SOCKET2, DOMAIN, TYPE, PROTOCOL )

cf L<perlfunc/socketpair>

=cut

# $_[0] and $_[1]: socket1, socket2
sub socketpair {
    my ( $domain, $type, $protocol ) = ( @_[ 2 .. 4 ] );

    local ( $!, $^E );
    return CORE::socketpair( $_[0], $_[1], $domain, $type, $protocol ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        # For now reuse socket()’s error class. Failures here should be
        # exceedingly rare, largely confined to cases of FD exhaustion.
        #
        die Cpanel::Exception::create( 'IO::SocketOpenError', [ domain => $domain, type => $type, protocol => $protocol, error => $err ] );
    };
}

1;
