package Cpanel::PEM;

# cpanel - Cpanel/PEM.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Context ();

=encoding utf-8

=head1 NAME

Cpanel::PEM - Utilities for managing PEM-formatted strings

=head1 SYNOPSIS

    my @pieces = Cpanel::PEM::split( $combined_pem );

=head1 DESCRIPTION

This module contains utilities for handling PEM files.

Note that CPAN’s L<Crypt::Format> can facilitate conversion between
DER and PEM formats.

=head1 FUNCTIONS

=head2 @pieces = split( $combined_pem_string )

This will take a “combined” PEM string (i.e., newline-joined PEM-formatted
strings) and return the individual PEM components. It is aassumed that there
is no trailing newline, and none of the returned elements will contain
trailing newlines.

=cut

sub split {
    my ($combined) = @_;

    Cpanel::Context::must_be_list();

    return split m[(?<=-) \n+ (?=-)]x, $combined;
}

=head2 strip_pem_formatting

Takes in an SSL key and strips out the BEGIN, END, and newlines leaving only the base64

=over 2

=item Input

=over 3

=item C<SCALAR>

The SSL key to strip

=back

=item Output

=over 3

=item C<SCALAR>

The base64 text of the key

=back

=back

=cut

sub strip_pem_formatting {

    my ($text) = @_;

    # This function is not intended to validate the base64
    # it just strips away the BEGIN and END. Adding validation
    # of the base64 will cause downline functions to fail
    # as they are expected to validate it.

    my ($base64) = $text =~ m{-+BEGIN[^\n]+-+\s*([^-]+)\s*-+END[^\n]+-+}s;

    return if !$base64;    #empty or very cert

    $base64 =~ tr{ \t\r\n\f}{}d;

    return if !$base64;

    return $base64;
}

1;
