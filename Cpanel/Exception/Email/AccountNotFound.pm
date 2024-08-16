package Cpanel::Exception::Email::AccountNotFound;

# cpanel - Cpanel/Exception/Email/AccountNotFound.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#   name
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'You do not have an email account named “[_1]”.',
        $self->get('name'),
    );
}

1;
