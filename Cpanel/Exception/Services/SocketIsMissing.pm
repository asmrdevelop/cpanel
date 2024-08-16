package Cpanel::Exception::Services::SocketIsMissing;

# cpanel - Cpanel/Exception/Services/SocketIsMissing.pm
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
#   socket
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The “[_1]” service failed because it cannot find the “[_2]” socket.',
        $self->get('service'), $self->get('socket') || ''
    );
}

1;
