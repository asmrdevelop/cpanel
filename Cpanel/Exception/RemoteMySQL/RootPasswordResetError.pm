package Cpanel::Exception::RemoteMySQL::RootPasswordResetError;

# cpanel - Cpanel/Exception/RemoteMySQL/RootPasswordResetError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new( 'Failed to reset [asis,MySQL] root password. Error: [_1]', $self->get('error') );
}

1;
