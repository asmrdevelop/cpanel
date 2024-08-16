package Cpanel::Exception::IO::StatError;

# cpanel - Cpanel/Exception/IO/StatError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   path    (optional; if not given, message is for a filehandle)
#   error
sub _default_phrase {
    my ($self) = @_;

    if ( defined $self->get('path') ) {
        return Cpanel::LocaleString->new(
            'The system failed to obtain filesystem information about “[_1]” because of an error: [_2]',
            ( map { $self->get($_) } qw( path error ) ),
        );
    }

    return Cpanel::LocaleString->new(
        'The system failed to obtain filesystem information about the node that a file handle references because of an error: [_2]',
        ( map { $self->get($_) } qw( path error ) ),
    );
}

1;
