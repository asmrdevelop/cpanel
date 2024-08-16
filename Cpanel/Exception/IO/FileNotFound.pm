package Cpanel::Exception::IO::FileNotFound;

# cpanel - Cpanel/Exception/IO/FileNotFound.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   path
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system cannot find a file named “[_1]”.',
        $self->{'_metadata'}{'path'},
    );
}

1;
