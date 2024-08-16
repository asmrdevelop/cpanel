package Cpanel::Exception::MissingParameters;

# cpanel - Cpanel/Exception/MissingParameters.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::MissingParameter );

use Cpanel::LocaleString ();

#Metadata parameters:
#   names
#
sub _default_phrase {
    my ($self) = @_;

    my $caller_name = $self->_get_caller_name();
    if ( !$caller_name ) {
        return Cpanel::LocaleString->new(
            'Provide the [list_and_quoted,_1] [numerate,_2,parameter,parameters].',
            $self->get('names'),
            scalar( @{ $self->get('names') } ),
        );
    }

    return Cpanel::LocaleString->new(
        'Provide the [list_and_quoted,_1] [numerate,_2,parameter,parameters] for the “[_3]” function.',
        $self->{'_metadata'}{'names'},
        scalar( @{ $self->{'_metadata'}{'names'} } ),
        $caller_name
    );
}

1;
