package Cpanel::Exception::IO::SymlinkReadError;

# cpanel - Cpanel/Exception/IO/SymlinkReadError.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   path
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to read “[_1]” as a symbolic link because of an error: [_2]',
        $self->get('path'),
        $self->get('error'),
    );
}

1;
