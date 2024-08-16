package Cpanel::Exception::IO::ReadError;

# cpanel - Cpanel/Exception/IO/ReadError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   length (bytes, optional)
#   path (optional)
#
sub _default_phrase {
    my ($self) = @_;

    die "Need “error”!" if !$self->get('error');

    if ( defined $self->get('length') ) {
        if ( $self->get('path') ) {
            return Cpanel::LocaleString->new(
                'The system failed to read up to [format_bytes,_1] from “[_2]” because of an error: [_3]',
                $self->get('length'),
                $self->get('path'),
                $self->get('error'),
            );
        }

        return Cpanel::LocaleString->new(
            'The system failed to read up to [format_bytes,_1] from a file handle because of an error: [_2]',
            $self->get('length'),
            $self->get('error'),
        );
    }

    if ( $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to read from “[_1]” because of an error: [_2]',
            $self->get('path'),
            $self->get('error'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to read from a file handle because of an error: [_1]',
        $self->get('error'),
    );
}

1;
