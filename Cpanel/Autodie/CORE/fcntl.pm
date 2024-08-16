package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/fcntl.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 fcntl( $FH, $FUNC, $SCALAR )

cf. L<perlfunc/fcntl>

=cut

sub fcntl {
    my ( $fh, $func, $scalar ) = @_;

    local ( $!, $^E );
    return fcntl( $fh, $func, $scalar ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::FcntlError', [ error => $err ] );
    };
}

1;
