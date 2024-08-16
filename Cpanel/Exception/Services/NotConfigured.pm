package Cpanel::Exception::Services::NotConfigured;

# cpanel - Cpanel/Exception/Services/NotConfigured.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(  Cpanel::Exception );

use Cpanel::LocaleString ();

#metadata parameters:
#   service
#
sub _default_phrase {
    my ($self) = @_;

    if ( $self->get('reason') ) {
        return Cpanel::LocaleString->new(
            'The “[_1]” service is not configured: [_2]',
            $self->get('service'), $self->get('reason')
        );
    }

    return Cpanel::LocaleString->new(
        'The “[_1]” service is not configured.',
        $self->get('service'),
    );
}

1;
