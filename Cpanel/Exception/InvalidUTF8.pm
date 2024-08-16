package Cpanel::Exception::InvalidUTF8;

# cpanel - Cpanel/Exception/InvalidUTF8.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::Encoder::ASCII ();
use Cpanel::LocaleString   ();

#Named parameters:
#
#   value   - required
#
sub _default_phrase {
    my ($self) = @_;

    my $legible = Cpanel::Encoder::ASCII::to_hex( $self->get('value') );

    return Cpanel::LocaleString->new(
        '“[_1]” is not valid [asis,UTF-8].',
        $legible,
    );
}

1;
