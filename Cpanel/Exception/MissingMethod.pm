package Cpanel::Exception::MissingMethod;

# cpanel - Cpanel/Exception/MissingMethod.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;
    my ( $method, $pkg ) = map { $self->get($_) } qw(method pkg);

    return Cpanel::LocaleString->new(
        'The “[_1]” method is missing in the “[_2]” class.',
        $method,
        $pkg
    );
}

1;
