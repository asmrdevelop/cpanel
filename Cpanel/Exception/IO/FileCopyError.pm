package Cpanel::Exception::IO::FileCopyError;

# cpanel - Cpanel/Exception/IO/FileCopyError.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Parameters:
#   source
#   destination
sub _default_phrase {
    my ($self) = @_;

    if ( $self->{'_metadata'}{'error'} ) {
        return Cpanel::LocaleString->new(
            'The system failed to copy the file “[_1]” to “[_2]” because of an error: “[_3]”.',
            @{ $self->{'_metadata'} }{qw( source destination error )},
        );

    }
    else {
        return Cpanel::LocaleString->new(
            'The system failed to copy the file “[_1]” to “[_2]” because of an error.',
            @{ $self->{'_metadata'} }{qw( source destination )},
        );
    }
}

1;
