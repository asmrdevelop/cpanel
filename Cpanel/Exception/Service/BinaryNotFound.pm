package Cpanel::Exception::Service::BinaryNotFound;

# cpanel - Cpanel/Exception/Service/BinaryNotFound.pm
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
#
sub _default_phrase {
    my ($self) = @_;

    my ( $binary, $service, $error ) = ( $self->get('binary'), $self->get('service'), $self->get('error') );

    if ( $service && !$binary && !$error ) {
        return Cpanel::LocaleString->new(
            'The system could not find the binary for the “[_1]” service.',
            $self->get('service'),
        );
    }

    return Cpanel::LocaleString->new(
        'The system could not find the “[_1]” binary for the “[_2]” service because of an error: [_3]',
        $self->get('binary'),
        $self->get('service'),
        $self->get('error'),
    );
}

1;
