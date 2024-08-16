package Cpanel::Exception::IO::WriteError;

# cpanel - Cpanel/Exception/IO/WriteError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   length
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to write [format_bytes,_1] to a file handle because of an error: [_2]',
        $self->get('length'),
        $self->get('error'),
    );
}

1;
