
# cpanel - Cpanel/ModSecurity.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ModSecurity;

use strict;
use warnings;

=head1 NAME

Cpanel::ModSecurity

=head2 has_modsecurity_installed()

Test if modsecurity is installed on the server

=cut

our $MODSEC_VERSION_FILE = '/etc/cpanel/ea4/modsecurity.version';

sub has_modsecurity_installed {
    require Cpanel::Autodie;
    return Cpanel::Autodie::exists($MODSEC_VERSION_FILE) ? 1 : 0;
}

1;
