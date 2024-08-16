package Cpanel::SafeFile::RW;

# cpanel - Cpanel/SafeFile/RW.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::SafeFile          ();
use Cpanel::SafeFile::Replace ();

sub safe_readwrite {
    my ( $file, $code_ref ) = @_;

    return if !defined $file || $file eq '' || ref $code_ref ne 'CODE';

    my $lockfh;
    if ( my $lockref = Cpanel::SafeFile::safeopen( $lockfh, '+<', $file ) ) {
        my $rclog = $code_ref->(
            $lockfh,
            sub {
                my $fh    = shift;
                my $newfh = Cpanel::SafeFile::Replace::safe_replace_content( $fh, $lockref, @_ );
                $lockfh = $newfh;
                return 1;
            }
        );

        Cpanel::SafeFile::safeclose( $lockfh, $lockref );

        return $rclog;
    }
    else {
        return;
    }
}

1;
