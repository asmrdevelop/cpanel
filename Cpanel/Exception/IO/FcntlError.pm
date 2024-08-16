package Cpanel::Exception::IO::FcntlError;

# cpanel - Cpanel/Exception/IO/FcntlError.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   path
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to manipulate a file descriptor because of an error: [_1]',
        $self->get('error'),
    );
}

1;
