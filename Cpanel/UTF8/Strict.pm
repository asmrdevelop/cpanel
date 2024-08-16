package Cpanel::UTF8::Strict;

# cpanel - Cpanel/UTF8/Strict.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::UTF8::Strict

=head1 SYNOPSIS

    # die()s on invalid UTF-8
    Cpanel::UTF8::Strict::decode( $string );

=head1 DESCRIPTION

A thin wrapper around Perl’s internal UTF-8 decoder.

B<NOTE:> If you just want to I<validate> a UTF-8 string, then see
L<Cpanel::Validate::UTF8>.

=head1 FUNCTIONS

=head2 decode( $STRING )

This function wraps L<utf8>’s C<decode()> with logic that
throws an exception on invalid generalized UTF-8.

(NB: Like’s C<decode()> itself, this accepts byte sequences that encode
code points, like unpaired surrogates, that UTF-8 forbids.)

B<NOTE:> The given $STRING is altered in-place.

=cut

sub decode {

    #This detects: http://www.perlmonks.org/?node_id=644786
    utf8::decode( $_[0] ) or do {
        local ( $@, $! );
        require Cpanel::Encoder::ASCII;
        die sprintf "Invalid UTF-8 in string: “%s”", Cpanel::Encoder::ASCII::to_hex( $_[0] );
    };

    # Leaving this return undocumented since it serves no useful purpose.
    return $_[0];
}

1;
