package Cpanel::Exception::DnsAdmin::DuplicateDnsUniqid;

# cpanel - Cpanel/Exception/DnsAdmin/DuplicateDnsUniqid.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Exception::DnsAdmin::DuplicateDnsUniqid

=head1 SYNOPSIS

    Cpanel::Exception::create('DnsAdmin::DuplicateDnsUniqid',
    "dnsadmin ended prematurely because it detected a duplicate dnsuniqid request for “$dnsuniqid”.");

=head1 DESCRIPTION

This exception class is for representing dnsadmin encountering
a duplicate dnsuniqid.

=cut

use parent qw( Cpanel::Exception );

1;
