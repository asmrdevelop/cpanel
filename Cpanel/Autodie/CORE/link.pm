package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/link.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 link( $OLDPATH, $NEWPATH )

cf. L<perlfunc/link>

=cut

sub link {
    my ( $old, $new ) = @_;

    local ( $!, $^E );
    return CORE::link( $old, $new ) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::LinkError', [ error => $err, oldpath => $old, newpath => $new ] );
    };
}

1;
