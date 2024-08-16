package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/rewinddir.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 rewinddir($FH)

cf. L<perlfunc/rewinddir>

=cut

sub rewinddir {
    my ($dh) = @_;

    local ( $!, $^E );
    return CORE::rewinddir($dh) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::DirectoryRewindError', [ error => $err ] );
    };
}

1;
