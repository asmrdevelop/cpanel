package Cpanel::Exception::IO::ForkError;

# cpanel - Cpanel/Exception/IO/ForkError.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to fork a new process because of an error: [_1]',
        $self->{'_metadata'}{'error'},
    );
}

1;
