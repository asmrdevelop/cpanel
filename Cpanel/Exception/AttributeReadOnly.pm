package Cpanel::Exception::AttributeReadOnly;

# cpanel - Cpanel/Exception/AttributeReadOnly.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Metadata parameters:
#   name
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'You cannot set the attribute “[_1]” because it is read-only.',
        $self->get('name'),
    );
}

1;
