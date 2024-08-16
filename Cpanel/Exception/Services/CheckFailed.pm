package Cpanel::Exception::Services::CheckFailed;

# cpanel - Cpanel/Exception/Services/CheckFailed.pm
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
#   message
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The service “[_1]” failed to start with the message: [_2]',
        $self->get('service'),
        $self->get('message'),
    );
}

1;
