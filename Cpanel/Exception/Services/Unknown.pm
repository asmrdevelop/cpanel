package Cpanel::Exception::Services::Unknown;

# cpanel - Cpanel/Exception/Services/Unknown.pm    Copyright 2022 cPanel, L.L.C.
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

    return Cpanel::LocaleString->new(
        'The “[_1]” service is not a known service.',
        $self->get('service'),
    );
}

1;
