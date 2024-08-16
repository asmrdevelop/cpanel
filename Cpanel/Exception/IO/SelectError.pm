package Cpanel::Exception::IO::SelectError;

# cpanel - Cpanel/Exception/IO/SelectError.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to multiplex filehandles because of an error: [_1]',
        $self->get('error'),
    );
}

1;
