package Cpanel::Exception::Services::BadResponse;

# cpanel - Cpanel/Exception/Services/BadResponse.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#metadata parameters:
#   service
#   error
#
#   … and either these two:
#       host
#       port
#
#   … or this:
#       socket (local socket path, not an actual Perl filehandle)
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('socket') ) {
        return Cpanel::LocaleString->new(
            'The service “[_1]” failed to send the expected response from the socket “[_2]” because of an error: [_3]',
            $self->get('service'),
            $self->get('socket'),
            $self->get('error')
        );

    }

    return Cpanel::LocaleString->new(
        'The service “[_1]” failed to send the expected response to host “[_2]” and port “[_3]” because of an error: [_4]',
        $self->get('service'),
        $self->get('host'),
        $self->get('port'),
        $self->get('error')
    );
}

1;
