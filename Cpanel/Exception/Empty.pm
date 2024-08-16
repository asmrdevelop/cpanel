package Cpanel::Exception::Empty;

# cpanel - Cpanel/Exception/Empty.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::InvalidParameter );

use Cpanel::LocaleString ();

#Parameters:
#   name - optional, the name of the parameter
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->{'_metadata'}{'name'} ) {
        return Cpanel::LocaleString->new(
            'The value of “[_1]” may not be empty.',
            $self->{'_metadata'}{'name'},
        );
    }

    return Cpanel::LocaleString->new('This value may not be empty.');
}

1;
