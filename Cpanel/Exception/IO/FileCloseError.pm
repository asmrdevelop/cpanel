package Cpanel::Exception::IO::FileCloseError;

# cpanel - Cpanel/Exception/IO/FileCloseError.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   path    - optional
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to close the file “[_1]” because of an error: [_2]',
            @{ $self->{'_metadata'} }{qw( path error )},
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to close an unknown file because of an error: [_1]',
        $self->get('error'),
    );
}

1;
