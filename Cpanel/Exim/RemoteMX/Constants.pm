package Cpanel::Exim::RemoteMX::Constants;

# cpanel - Cpanel/Exim/RemoteMX/Constants.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exim::RemoteMX::Constants

=head1 CONSTANTS

=head2 PATH()

The filesystem path to the remote MX IP address datastore.

=cut

use constant IP_SEPARATOR => ':';
use constant PATH         => '/etc/domain_remote_mx_ips.cdb';

1;
