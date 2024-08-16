package Cpanel::Exception::InvalidUsername;

# cpanel - Cpanel/Exception/InvalidUsername.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Named parameters:
#
#   value   - required, the value that not a valid username
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        '“[_1]” is not a valid username on this system.',
        $self->get('value'),
    );
}

1;
