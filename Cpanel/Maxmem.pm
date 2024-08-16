package Cpanel::Maxmem;

# cpanel - Cpanel/Maxmem.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# IMPORTANT: keep this module light as it's included by cpsrvd, cpdavd...
#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::Maxmem

=head1 SYNOPSIS

    my $default = Cpanel::Maxmem::default();
    my $minimum = Cpanel::Maxmem::minimum();

=head1 DESCRIPTION

This module computes minimum and default values of the C<maxmem> setting in
F</var/cpanel/cpanel.config>.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains::Count ();

#NB: Keep this in sync with
#Cpanel::Config::CpConfGuard::Default::default_statics().
use constant _INITIAL_DEFAULT => 4096;

sub _count_domains {

    # If we're unprivileged, assume that there's only one domain.
    return eval { Cpanel::Config::LoadUserDomains::Count::countuserdomains() } // 1;
}

# use a function rather than a constant as this can be system dependent
#   using Cpanel::Config::Constants can also be an alternate solution at this time

=head2 minimum()

Returns the minimum value of the setting.

=cut

sub minimum {
    return _INITIAL_DEFAULT() * ( 1 + int( _count_domains() / 10_000 ) );
}

=head2 minimum()

Returns the default value of the setting.

=cut

# currently the default value is the same as the minimum
*default = *minimum;

1;
