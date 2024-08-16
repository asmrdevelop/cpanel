package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/truncate.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 truncate()

cf. L<perlfunc/truncate>

=cut

sub truncate {
    my ( $fh_or_expr, $length ) = @_;

    local ( $!, $^E );
    return CORE::truncate( $fh_or_expr, $length ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::FileTruncateError', [ error => $err, length => $length ] );
    };
}

1;
