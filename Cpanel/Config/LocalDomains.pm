
# cpanel - Cpanel/Config/LocalDomains.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Config::LocalDomains;

use strict;

#Exposed as a global for testing.
our $_LOCALDOMAINS_FILE = '/etc/localdomains';

#TODO: This should die() on failure.
sub loadlocaldomains {
    my %LD;

    open( my $ld_fh, '<', $_LOCALDOMAINS_FILE ) or do {
        warn "Failed to open $_LOCALDOMAINS_FILE: $!";
        return wantarray ? () : {};
    };

    while ( my $ld = readline($ld_fh) ) {
        chomp($ld);
        $LD{$ld} = 1;
    }

    close($ld_fh);

    return \%LD;
}

1;
