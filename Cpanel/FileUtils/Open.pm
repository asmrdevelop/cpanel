package Cpanel::FileUtils::Open;

# cpanel - Cpanel/FileUtils/Open.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Fcntl ();

#Same as Perl sysopen(), but the perms you pass in are actual perms,
#not a bitmask.
#
#Also, as a convenience, you can pass in a pipe-delimited string
#of O_* constants (e.g., 'O_RDWR|O_NOFOLLOW'), and this will translate
#that into the corresponding numeric mode.
#
#NOTE: It is by design that simple identifier filehandles do NOT work
#with this function. If that functionality is needed it can be added,
#but scalars or typeglob references should do just fine.
#
sub sysopen_with_real_perms {    ##no critic qw(RequireArgUnpacking)
                                 # $_[0]: fh
    my ( $file, $mode, $custom_perms ) = ( @_[ 1 .. 3 ] );

    if ( $mode && substr( $mode, 0, 1 ) eq 'O' ) {
        $mode = Cpanel::Fcntl::or_flags( split m<\|>, $mode );
    }

    my ( $sysopen_perms, $original_umask );

    if ( defined $custom_perms ) {
        $custom_perms &= 0777;
        $original_umask = umask( $custom_perms ^ 07777 );
        $sysopen_perms  = $custom_perms;
    }
    else {
        $sysopen_perms = 0666;
    }

    my $ret = sysopen( $_[0], $file, $mode, $sysopen_perms );

    if ( defined $custom_perms ) {

        # () = is faster.  No idea why
        () = umask($original_umask);
    }

    return $ret;
}

1;
