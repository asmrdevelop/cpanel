package Cpanel::AcctUtils::DomainOwner::BAMP;

# cpanel - Cpanel/AcctUtils/DomainOwner/BAMP.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AcctUtils::DomainOwner::Tiny ();

#NOTE: "BAMP" = "By Any Means Possible"
sub getdomainownerBAMP {
    my $domain = shift;
    my $opref  = shift;

    my $owner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $domain, $opref );
    if ($owner) { return $owner; }

    my @DNSPATH    = split( /\./, lc($domain) );
    my @SEARCHPATH = pop(@DNSPATH);
    while ( $#DNSPATH > 0 ) {
        unshift( @SEARCHPATH, pop(@DNSPATH) );
        my $searchdomain    = join( '.', @SEARCHPATH );
        my $rootdomainowner = Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner( $searchdomain, $opref );
        if ($rootdomainowner) { return $rootdomainowner; }
    }

    return;
}

1;
