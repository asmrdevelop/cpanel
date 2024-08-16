package Cpanel::Exception::IO::CloseError;

# cpanel - Cpanel/Exception/IO/CloseError.pm       Copyright 2022 cPanel, L.L.C.
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

    if ( my $filename = $self->get('filename') ) {
        return Cpanel::LocaleString->new(
            'The system failed to close a file handle for “[_1]” because of the following error: [_2]',
            $filename, $self->get('error'),
        );

    }

    return Cpanel::LocaleString->new(
        'The system failed to close a file handle because of an error: [_1]',
        $self->get('error'),
    );
}

1;
