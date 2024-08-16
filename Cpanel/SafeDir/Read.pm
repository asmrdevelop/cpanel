package Cpanel::SafeDir::Read;

# cpanel - Cpanel/SafeDir/Read.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

sub read_dir {
    my ( $dir, $coderef ) = @_;
    my @contents;
    if ( opendir my $dir_dh, $dir ) {
        @contents = grep { $_ ne '.' && $_ ne '..' } readdir($dir_dh);
        if ($coderef) {
            @contents = grep { $coderef->($_) } @contents;
        }
        closedir $dir_dh;
        return wantarray ? @contents : \@contents;
    }
    return;
}

1;
