package Cpanel::Exception::SystemCall::Unsupported;

# cpanel - Cpanel/Exception/SystemCall/Unsupported.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Exception);

use Cpanel::LocaleString ();

#Named arguments:
#   name
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'This system does not support the system call “[_1]”.',
        $self->get('name'),
    );
}

1;
