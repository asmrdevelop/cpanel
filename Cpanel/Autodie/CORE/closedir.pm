package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/closedir.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 closedir( $FH )

cf. L<perlfunc/closedir>

=cut

sub closedir {
    my ($dh) = @_;

    local ( $!, $^E );
    return CORE::closedir($dh) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::DirectoryCloseError', [ error => $err ] );
    };
}

1;
