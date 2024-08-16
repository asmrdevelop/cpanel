package Cpanel::Exception::IO::DirectoryReadError;

# cpanel - Cpanel/Exception/IO/DirectoryReadError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
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
        'The system failed to read the directory “[_1]” because of an error: [_2]',
        @{ $self->{'_metadata'} }{qw(path error)},
    );
}

1;
