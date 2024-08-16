package Cpanel::IPv6::Normalize;

# cpanel - Cpanel/IPv6/Normalize.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Validate::IP ();
use Cpanel::IP::Expand   ();

use constant DOES_NOT_HAVE_IPV6_STRING => 'n/a';

=encoding utf-8

=head1 NAME

Cpanel::IPv6::Normalize - Tools to validate and normalize IPv6 addresses

=head1 SYNOPSIS

    use Cpanel::IPv6::Normalize;

    my($ok, $expanded_ipv6) = Cpanel::IPv6::Normalize::normalize_ipv6_address($possible_ipv6);

=cut

=head2 normalize_ipv6_address($address)

Make sure we are working with a valid IPv6 address in the correct format.

If the passed in address is valid, this function will return:

(1, Expanded IPv6 Address)

If the passed in address is not valid, this function will return:

(0, ERROR STRING)

=cut

sub normalize_ipv6_address {
    my ($address) = @_;

    if ( !length $address ) {
        return ( 0, "normalize_ipv6_address requires an IPv6 address" );
    }

    if ( !Cpanel::Validate::IP::is_valid_ipv6($address) ) {
        return ( 0, "“$address” is not a valid IPv6 address" );
    }

    return ( 1, Cpanel::IP::Expand::expand_ip( $address, 6 ) );
}

1;
