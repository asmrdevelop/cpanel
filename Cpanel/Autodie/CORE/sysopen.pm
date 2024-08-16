package Cpanel::Autodie;

# cpanel - Cpanel/Autodie/CORE/sysopen.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 FUNCTIONS

=head2 sysopen()

cf. L<perlfunc/sysopen>

B<NOTE:> Like the C<sysopen()> built-in, this will always auto-vivify a
filehandle, even on failure. That may change eventually, but for now
we mimic the built-in’s behavior even to a fault.

=cut

sub sysopen {    ## no critic(RequireArgUnpacking)
                 # $_[0]: fh
    my @post_handle_args = ( @_[ 1 .. $#_ ] );

    my ( $path, $mode, $perms ) = @post_handle_args;

    local ( $!, $^E );

    my $ret;
    if ( @post_handle_args < 3 ) {
        $ret = CORE::sysopen( $_[0], $path, $mode );
    }
    else {
        $ret = CORE::sysopen( $_[0], $path, $mode, $perms );
    }

    if ( !$ret ) {
        my $err = $!;

        local $@;
        require Cpanel::Exception;

        require Cpanel::FileUtils::Attr;
        my $attributes = Cpanel::FileUtils::Attr::get_file_or_fh_attributes($path);

        die Cpanel::Exception::create( 'IO::FileOpenError', [ path => $path, mode => $mode, error => $err, permissions => $perms, immutable => $attributes->{'IMMUTABLE'}, 'append_only' => $attributes->{'APPEND_ONLY'} ] );
    }

    return $ret;
}

1;
