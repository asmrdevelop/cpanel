package Cpanel::LocaleString::Raw;

# cpanel - Cpanel/LocaleString/Raw.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::LocaleString::Raw - a “fake” locale string

=head1 SYNOPSIS

    my $str = Cpanel::LocaleString::Raw->new( $some_text );

    print $str->to_string();

=head1 DESCRIPTION

This little shim module emulates enough of L<Cpanel::LocaleString>
to be useful in contexts where you have some non-localizable text
that needs to be in the same list as localizable text.

=head1 METHODS

=head2 I<CLASS>->new( STRING )

Instantiates this class.

=cut

sub new {
    my ( $class, $string ) = @_;

    return bless \$string, $class;
}

=head2 I<OBJ>->to_string()

Returns the original C<STRING> given to the constructor.

=cut

sub to_string { return ${ $_[0] } }

*TO_JSON = \&to_string;

1;
