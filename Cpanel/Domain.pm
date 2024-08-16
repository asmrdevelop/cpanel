package Cpanel::Domain;

# cpanel - Cpanel/Domain.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

sub Domain_init { }

sub Domain_getdomaincount {
    $Cpanel::CPVAR{'domaincount'}     = scalar @Cpanel::DOMAINS;
    $Cpanel::CPVAR{'hasmultidomains'} = $Cpanel::CPVAR{'domaincount'} > 1 ? 1 : 0;
}

1;
