package Cpanel::Services::AlwaysInstalled;

# cpanel - Cpanel/Services/AlwaysInstalled.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Services::AlwaysInstalled

=head1 DESCRIPTION

This module consists of a constant list of names of services that are always
installed.

=head1 FUNCTIONS

=head2 SERVICES()

Returns a list of names of services that are always installed in
cPanel & WHM. The names are in a format that L<Cpanel::Services::Installed>
understands.

=cut

use constant SERVICES => (
    'cpanel_php_fpm',
    'cpgreylistd',
    'cphulkd',
    'cpsrvd',
    'dnsadmin',
    'ipaliases',
    'lmtp',
    'named',
    'queueprocd',
    'tailwatchd',
);

1;
