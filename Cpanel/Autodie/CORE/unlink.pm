package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/unlink.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 unlink( $PATH )

cf. L<perlfunc/unlink>

B<NOTE:> Maybe you want C<unlink_if_exists()> instead?

B<NOTE:> This will only unlink one path at a time. It refuses to support
multiple C<unlink()> operations within the same call. This is in order to
provide reliable error reporting.

You, of course, can still do C<Cpanel::Autodie::unlink() for @files;>.

=cut

sub unlink {
    my (@paths) = @_;

    #This is here because it's impossible to do reliable error-checking when
    #you operate on >1 filesystem node at once.
    die "Only one path at a time!" if @paths > 1;

    if ( !@paths ) {
        @paths = ($_);
    }

    local ( $!, $^E );
    return CORE::unlink(@paths) || do {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        die Cpanel::Exception::create( 'IO::UnlinkError', [ error => $err, path => \@paths ] );
    };
}

1;
