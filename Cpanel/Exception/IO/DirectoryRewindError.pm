package Cpanel::Exception::IO::DirectoryRewindError;

# cpanel - Cpanel/Exception/IO/DirectoryRewindError.pm
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
            'The system failed to rewind its handle for the directory “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to rewind a directory handle because of an error: [_1]',
        $self->get('error'),
    );
}

1;
