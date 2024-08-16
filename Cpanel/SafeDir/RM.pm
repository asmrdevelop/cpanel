package Cpanel::SafeDir::RM;

# cpanel - Cpanel/SafeDir/RM.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#XXX This will, for legacy reasons, set global $?.
#Be sure that, when you call this, you do “local $?” if you are
#prospectively within a DESTROY handler, as it’s possible to
#“coerce” Perl into exiting 0 even from an untrapped exception:
#
#https://rt.perl.org/Ticket/Display.html?id=127386
#
sub safermdir {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return   if !-d $_[0];
    return 1 if rmdir( $_[0] );
    if ( opendir( my $dh, $_[0] ) ) {
        while ( my $file = readdir($dh) ) {
            next if $file eq '.' || $file eq '..';
            unlink("$_[0]/$file") or last;
        }
    }
    return 1 if rmdir( $_[0] );
    require File::Path;
    File::Path::rmtree( $_[0] );

    if ( !-d $_[0] ) {

        # dir was deleted, but for reasons unknown $_ will return
        # -1.  Yet it did the work, go figure

        $? = 0;
        return 1;
    }

    return;
}

1;
