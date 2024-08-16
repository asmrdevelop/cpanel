package Cpanel::UTF8::Utils;

# cpanel - Cpanel/UTF8/Utils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Carp ();

use Cpanel::UTF8::Strict ();

=head1 MODULE

C<Cpanel::UTF8::Utils>

=head1 DESCRIPTION

C<Cpanel::UTF8::Utils> contains functions which make handling of UTF8-encoded
strings easier.

=head2 quotemeta(STRING)

The Perl C<quotemeta()> built-in does not handle encoded strings very well,
often escaping each byte of multibyte characters separately. This wrapper
function decodes the UTF-8 into a string of pure Unicode codepoints, which
C<quotemeta()> does handle appropriately, then re-encodes.

=cut

sub quotemeta {
    push @_, \&Carp::carp;
    goto &Cpanel::UTF8::Utils::_quotemeta;
}

=head2 quotemeta_or_die(STRING)

This does the same thing as the previous C<quotemeta()> wrapper, except it dies if the parameter is undefined.

=cut

sub quotemeta_or_die {
    push @_, \&Carp::croak;
    goto &Cpanel::UTF8::Utils::_quotemeta;
}

sub _quotemeta {
    my ( $quotable, $handler ) = @_;
    if ( !defined $quotable ) {
        $handler->("Use of uninitialized value in quotemeta");
        return '';    # Yes, this is what the built-in returns for undef.
    }

    # Suppress exception, since failure is a valid result here.
    local $@;
    my $is_decoded = eval { Cpanel::UTF8::Strict::decode($quotable) };
    my $quoted     = CORE::quotemeta $quotable;
    utf8::encode($quoted) if $is_decoded;    # Re-encode if previously decoded.

    return $quoted;
}

1;
