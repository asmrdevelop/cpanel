package Cpanel::Exception::MissingParameter;

# cpanel - Cpanel/Exception/MissingParameter.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::Caller );

use Cpanel::LocaleString ();

#Metadata parameters:
#   name
#
sub _default_phrase {
    my ($self) = @_;

    my $caller_name = $self->_get_caller_name();
    if ( !$caller_name ) {
        return Cpanel::LocaleString->new(
            'Provide the “[_1]” parameter.',
            $self->get('name'),
        );
    }

    return Cpanel::LocaleString->new(
        'Provide the “[_1]” parameter for the “[_2]” function.',
        $self->{'_metadata'}{'name'},
        $caller_name
    );
}

1;
