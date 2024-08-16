package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/link_if_no_conflict.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 link_if_no_conflict( $OLDPATH, $NEWPATH )

Like C<link()> but will return undef on EEXIST rather than
throwing an exception.

=cut

sub link_if_no_conflict {
    my ( $old, $new ) = @_;

    local ( $!, $^E );
    return CORE::link( $old, $new ) || do {
        return 0 if $! == _EEXIST();

        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::LinkError', [ error => $err, oldpath => $old, newpath => $new ] );
    };
}

1;
