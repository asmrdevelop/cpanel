package Cpanel::Exception::FunctionNotImplemented;

# cpanel - Cpanel/Exception/FunctionNotImplemented.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception );

use Cpanel::LocaleString ();

#Params:
#  name - name of the function/method
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The function “[_1]” has not been implemented. Override this function in a subclass.',
        $self->{'_metadata'}{'name'},
    );
}

1;
