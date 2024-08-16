package Cpanel::Validate::Punycode;

# cpanel - Cpanel/Validate/Punycode.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Validate::Punycode

=head1 SYNOPSIS

    $is_valid = is_valid( $specimen )

=cut

use Cpanel::Encoder::Punycode ();

=head1 FUNCTIONS

=head2 VALID_YN = is_valid( SPECIMEN )

The return value is a boolean that indicates whether SPECIMEN is
a valid punycode string. Note that non-punycode strings are considered
valid; this only returns falsey if the string “looks like” punycode
(i.e., contains C<xn-->) but isn’t valid as such.

=cut

sub is_valid {
    my ($domain) = @_;

    return 1 if index( $domain, 'xn--' ) == -1;
    local $@;
    my $decoded = eval { Cpanel::Encoder::Punycode::punycode_decode_str($domain) };
    return 0 if $@;
    return index( $decoded, 'xn--' ) == -1;
}

=head1 SEE ALSO

This uses L<Cpanel::Encoder::Punycode> internally.

=cut

1;
