package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/close.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 close( $FH )

cf. L<perlfunc/close>

=cut

# Note: filename is optional.  It is only used to provide a more useful error message
# when the exception is thrown
sub close {
    my ( $fh, $filename ) = @_;

    local ( $!, $^E );
    return ( $fh ? CORE::close($fh) : CORE::close() ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::CloseError', [ error => $err, filename => $filename ] );
    };
}

1;
