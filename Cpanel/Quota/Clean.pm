package Cpanel::Quota::Clean;

# cpanel - Cpanel/Quota/Clean.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Quota::Temp ();

sub zero_quota {
    my $uid = shift;

    my $tempquota = Cpanel::Quota::Temp->new( user => $uid );
    $tempquota->disable();
    $tempquota->norestore();
}

1;
