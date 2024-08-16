package Cpanel::API::BlockIP;

# cpanel - Cpanel/API/BlockIP.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf8

=head1 NAME

Cpanel::API::BlockIP

=head1 DESCRIPTION

This module contains UAPI methods related to BlockIP.

=head1 SYNOPSIS


  use Cpanel::API::BlockIP ();

  # Block an IP
  Cpanel::API::BlockIP::add_ip('100.1.1.2');

  # Unblock an IP
  Cpanel::API::BlockIP::remove_ip('100.1.1.122');

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::DenyIp ();

my $non_mutating = { allow_demo => 1 };
my $mutating     = {};

our %API = (
    _needs_role    => 'WebServer',
    _needs_feature => 'ipdeny',
    add_ip         => $mutating,
    remove_ip      => $mutating
);

=head2 add_ip()

=head3 ARGUMENTS

=over

=item ip - string

The ip or range to block. There are several formats supported:

=over 1

=item 192.168.0.1 - Single IPv4 Address

=item 2001:db8::1 - Single IPv6 Address

=item 192.168.0.1-192.168.0.58 - IPv4 Range

=item 2001:db8::1-2001:db8::3 - IPv6 Range

=item 192.168.0.1-58 - Implied Range

=item 192.168.0.1/16 - CIDR Format IPv4

=item 2001:db8::/32 - CIDR Format IPv6

=item 10. - Matches 10.*.*.*

=back

=back

=head3 RETURNS

On success, the method returns an arrayref containing the IP addresses blocked.

=head3 THROWS

=over

=item When the WebServer Role or C<ipdeny> feature are not enabled.

=item When the account is in demo mode.

=item When a hostname cannot be resolved.

=item When given invalid IP's or ranges.

=item Other errors from additional modules used.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BlockIP add_ip ip=100.1.1.1

The returned data will contain a structure similar to the JSON below:

    "data" : [
       "100.1.1.1"
    ]

=head4 Template Toolkit

    [%
    SET result = execute('BlockIP', 'add_ip', {
        ip => '100.1.1.1'
    });
    IF result.status;
        FOREACH item IN result.data %]
            Blocked: [% item.html() %]
        [% END %]
    [% END %]


=cut

sub add_ip {
    my ( $args, $result ) = @_;

    my $ip = $args->get_length_required('ip');
    $result->data( Cpanel::DenyIp::add_ip($ip) );

    return 1;
}

=head2 remove_ip()

=head3 ARGUMENTS

=over

=item ip - string

The ip or range to unblock. There are several formats supported:

=over 1

=item 192.168.0.1 - Single IPv4 Address

=item 2001:db8::1 - Single IPv6 Address

=item 192.168.0.1-192.168.0.58 - IPv4 Range

=item 2001:db8::1-2001:db8::3 - IPv6 Range

=item 192.168.0.1-58 - Implied Range

=item 192.168.0.1/16 - CIDR Format IPv4

=item 2001:db8::/32 - CIDR Format IPv6

=item 10. - Matches 10.*.*.*

=back

=back

=head3 RETURNS

On success, the method returns an arrayref containing the IP addresses unblocked.

=head3 THROWS

=over

=item When the WebServer Role or C<ipdeny> feature are not enabled.

=item When the account is in demo mode.

=item When a hostname cannot be resolved.

=item When given invalid IP's or ranges.

=item Other errors from additional modules used.

=back

=head3 EXAMPLES

=head4 Command line usage

    uapi --user=cpuser --output=jsonpretty BlockIP remove_ip ip=100.1.1.1

The returned data will contain a structure similar to the JSON below:

    "data" : [
       "100.1.1.1"
    ]

=head4 Template Toolkit

    [%
    SET result = execute('BlockIP', 'remove_ip', {
        ip => '100.1.1.1'
    });
    IF result.status;
        FOREACH item IN result.data %]
            Unblocked: [% item.html() %]
        [% END %]
    [% END %]

=cut

sub remove_ip {
    my ( $args, $result ) = @_;

    my $ip = $args->get_length_required('ip');
    $result->data( Cpanel::DenyIp::remove_ip($ip) );

    return 1;
}

1;
