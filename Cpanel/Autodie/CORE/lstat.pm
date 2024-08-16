package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/lstat.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 lstat( $PATH_OR_FH )

cf. L<perlfunc/lstat>

=cut

#NOTE: To get lstat(_), do lstat(\*_).
sub lstat {
    my ($path_or_fh) = @_;

    local ( $!, $^E );

    my $ret = wantarray ? [ CORE::lstat($path_or_fh) ] : CORE::lstat($path_or_fh);

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
