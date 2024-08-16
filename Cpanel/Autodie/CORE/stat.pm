package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/stat.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 stat()

cf. L<perlfunc/stat>


B<NOTE:> To mimic the functionality of C<stat(_)>, do C<stat(\*_)>,
though since Perl is just reading from memory—which should never
fail!—there’s little point to doing this.

=cut

sub stat {
    my ($path_or_fh) = @_;

    local ( $!, $^E );

    my $ret = wantarray ? [ CORE::stat($path_or_fh) ] : CORE::stat($path_or_fh);

    if ( wantarray ? !@$ret : !$ret ) {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        require Cpanel::FHUtils::Tiny;

        if ( Cpanel::FHUtils::Tiny::is_a($path_or_fh) ) {
            die Cpanel::Exception::create( 'IO::StatError', [ error => $err ] );
        }

        die Cpanel::Exception::create( 'IO::StatError', [ error => $err, path => $path_or_fh ] );
    }

    return wantarray ? @$ret : $ret;
}

1;
