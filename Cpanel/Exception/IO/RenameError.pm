package Cpanel::Exception::IO::RenameError;

# cpanel - Cpanel/Exception/IO/RenameError.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   oldpath
#   newpath
#   error
sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        'The system failed to rename “[_1]” to “[_2]” because of an error: [_3]',
        @{ $self->{'_metadata'} }{qw( oldpath newpath error )},
    );
}

1;
