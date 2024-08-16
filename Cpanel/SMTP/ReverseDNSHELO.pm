package Cpanel::SMTP::ReverseDNSHELO;

# cpanel - Cpanel/SMTP/ReverseDNSHELO.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SMTP::ReverseDNSHELO

=head1 DESCRIPTION

This subclass of L<Cpanel::Config::TouchFileBase> implements storage
for the toggle to use reverse DNS for SMTP HELO.

=cut

use parent 'Cpanel::Config::TouchFileBase';

use constant _TOUCH_FILE => '/var/cpanel/use_rdns_for_helo';

1;
