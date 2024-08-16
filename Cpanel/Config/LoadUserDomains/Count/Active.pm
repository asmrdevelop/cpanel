package Cpanel::Config::LoadUserDomains::Count::Active;

# cpanel - Cpanel/Config/LoadUserDomains/Count/Active.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains::Count ();

=head1 NAME

Cpanel::Config::LoadUserDomains::Count::Active

=cut

=head2 count_active_trueuserdomains()

Count the number of main domains (cpanel users) on the system
minus suspended domains

=cut

sub count_active_trueuserdomains {
    my $true_users = Cpanel::Config::LoadUserDomains::Count::counttrueuserdomains() or return 0;
    require Whostmgr::Accounts::Suspended;
    my $suspended             = Whostmgr::Accounts::Suspended::getsuspendedlist( undef, undef, undef, 0 );
    my $number_of_suspensions = 0;
    if ( ref $suspended ) {
        $number_of_suspensions = scalar( keys %$suspended );
    }

    return $true_users - $number_of_suspensions;
}

1;
