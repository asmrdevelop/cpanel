package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/opendir.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=head1 FUNCTIONS

=head2 opendir( $DIRHANDLE, $PATH )

cf. L<perlfunc/opendir>

=cut

# $_[0]: dir_handle
# $_[1]: dir_name
sub opendir {
    return opendir_if_exists(@_) // do {
        local $! = _ENOENT();
        die _diropenerr( $_[1], $! );
    };
}

sub opendir_if_exists {
    local ( $!, $^E );
    return CORE::opendir( $_[0], $_[1] ) || do {
        if ( $! != _ENOENT() ) {
            my $err = $!;

            local $@;
            require Cpanel::Exception;

            die _diropenerr( $_[1], $err );
        }

        undef;
    };
}

sub _diropenerr {
    my ( $path, $err ) = @_;

    local $@;
    require Cpanel::Exception;
    die Cpanel::Exception::create( 'IO::DirectoryOpenError', [ path => $path, error => $err ] );
}

1;
