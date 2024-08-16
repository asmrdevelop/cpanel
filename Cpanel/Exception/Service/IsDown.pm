package Cpanel::Exception::Service::IsDown;

# cpanel - Cpanel/Exception/Service/IsDown.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Parameters:
#
#   service - optional, the name of the service
#
#   message - optional, more details about the service being down.
#       Only parsed if “service” is also given.
#
sub _default_phrase {
    my ($self) = @_;

    if ( length $self->{'_metadata'}{'service'} && length $self->{'_metadata'}{'message'} ) {
        return Cpanel::LocaleString->new(
            'The “[_1]” service is down: [_2]',
            $self->{'_metadata'}{'service'},
            $self->{'_metadata'}{'message'},
        );
    }
    elsif ( length $self->{'_metadata'}{'service'} ) {
        return Cpanel::LocaleString->new(
            'The “[_1]” service is down.',
            $self->{'_metadata'}{'service'},
        );
    }

    return Cpanel::LocaleString->new('The service is down.');
}

1;
