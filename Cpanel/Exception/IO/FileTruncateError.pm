package Cpanel::Exception::IO::FileTruncateError;

# cpanel - Cpanel/Exception/IO/FileTruncateError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   path    (optional)
#   error
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to truncate the file “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to truncate a file because of an error: [_1]',
        $self->get('error'),
    );
}

1;
