package Cpanel::Email::Maildir::Counter;

# cpanel - Cpanel/Email/Maildir/Counter.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile ();

# Note: this file is no longer used in exim as of v68

sub maildirsizecounter {
    my ($maildirsizef) = @_;

    my $has_data  = 0;
    my $count     = 0;
    my $filecount = 0;

    my @lines = split( m{\n}, Cpanel::LoadFile::load($maildirsizef) );
    $has_data = 1 if scalar @lines >= 2;
    foreach (@lines) {
        if (m/^[ \t]*(\-?[0-9]+)[ \t]+(\-?[0-9]+)/) {
            $count     += $1;
            $filecount += $2;
        }
    }

    return ( $has_data, $count, $filecount );
}

1;
