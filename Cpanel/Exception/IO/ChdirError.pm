package Cpanel::Exception::IO::ChdirError;

# cpanel - Cpanel/Exception/IO/ChdirError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   path (optional)
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to change a process’s current directory to “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to change a process’s current directory because of an error: [_1]',
        $self->get('error'),
    );
}

1;
