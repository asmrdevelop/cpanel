package Cpanel::Exception::Services::ReloadError;

# cpanel - Cpanel/Exception/Services/ReloadError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(  Cpanel::Exception::SubProcessError );

use Cpanel::LocaleString ();

#metadata parameters:
#   service
#   error
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The “[_1]” service failed to reload because the reload script exited with an error: [_2]',
        $self->get('service'),
        $self->get('error')
    );
}

1;
