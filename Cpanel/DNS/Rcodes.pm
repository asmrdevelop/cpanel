package Cpanel::DNS::Rcodes;

# cpanel - Cpanel/DNS/Rcodes.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Rcodes

=head1 CONSTANTS

=head2 RCODES()

An arrayref of DNS rcode names, in order.

=cut

# https://www.iana.org/assignments/dns-parameters/dns-parameters.xhtml#dns-parameters-6
# TODO: Use “name”s as given in the table.
use constant RCODES => [
    qw(
      NOERROR
      FORMERR
      SERVFAIL
      NXDOMAIN
      NOTIMPL
      REFUSED
      YXDOMAIN
      YXRRSET
      NXRRSET
      NOTAUTH
      NOTZONE
    )
];

1;
