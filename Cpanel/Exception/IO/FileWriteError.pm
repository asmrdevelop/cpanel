package Cpanel::Exception::IO::FileWriteError;

# cpanel - Cpanel/Exception/IO/FileWriteError.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IO::WriteError );

use Cpanel::LocaleString ();

#metadata parameters:
#   error
#   path    - optional
#
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to write to the file “[_1]” because of an error: [_2]',
        @{ $self->{'_metadata'} }{qw(path error)},
    );
}

1;
