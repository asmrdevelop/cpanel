package Cpanel::Exception::InvalidUTF8::CodePoint;

# cpanel - Cpanel/Exception/InvalidUTF8/CodePoint.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::InvalidUTF8 );

use Cpanel::Encoder::ASCII ();
use Cpanel::LocaleString   ();

#Named parameters:
#
#   value       - required, string
#   code_point  - required, number
#
sub _default_phrase {
    my ($self) = @_;

    my $legible = Cpanel::Encoder::ASCII::to_hex( $self->get('value') );

    my $hex_code_point = sprintf 'U+%x', $self->get('code_point');

    return Cpanel::LocaleString->new(
        '“[_1]” contains a Unicode code point ([_2]) that is not valid according to [asis,RFC 3629].',
        $legible,
        $hex_code_point,
    );
}

1;
