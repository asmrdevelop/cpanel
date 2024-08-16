package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/rename_if_exists.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 rename_if_exists( $OLDNAME => $NEWNAME )

Like C<rename()> but will return undef rather than
throwing an exception on ENOENT.

=cut

sub rename_if_exists {
    my ( $old, $new ) = @_;

    local ( $!, $^E );
    return CORE::rename( $old, $new ) || do {
        return 0 if $! == _ENOENT();

        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::RenameError', [ error => $err, oldpath => $old, newpath => $new ] );
    };
    return 0;
}

1;
