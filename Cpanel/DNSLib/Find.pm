package Cpanel::DNSLib::Find;

# cpanel - Cpanel/DNSLib/Find.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub find_rndc {
    my $self = shift;
    my @LOC  = qw( /usr/sbin/rndc /usr/local/sbin/rndc /usr/sbin/ndc /usr/local/sbin/ndc );

    foreach my $loc (@LOC) {
        if ( -x $loc ) {
            my @path_parts = split( /\//, $loc );
            my $program    = pop @path_parts;
            return wantarray ? ( $loc, $program ) : $loc;
        }
    }
    return;
}

1;
