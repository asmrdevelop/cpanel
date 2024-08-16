package Cpanel::DNSSEC::Available;

# cpanel - Cpanel/DNSSEC/Available.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DNSSEC::Available

=head1 DESCRIPTION

This module normalizes logic to determine if DNSSEC is available via the
local system’s nameserver.

As of this writing, only one supported nameserver—PowerDNS—provides DNSSEC
to cPanel & WHM; however, in case that changes in the future, it’s better
to use this module to determine DNSSEC capability rather than to read
the system configuration directly.

=cut

#----------------------------------------------------------------------

use Cpanel::Services::Enabled ();
use Cpanel::NameServer::Conf  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = dnssec_is_available()

Returns a boolean that indicates if the server provides DNSSEC
capability.

=cut

sub dnssec_is_available() {
    return Cpanel::Services::Enabled::is_provided('named') && Cpanel::NameServer::Conf->new()->can('secure_zone') ? 1 : 0;
}

1;
