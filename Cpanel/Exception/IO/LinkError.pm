package Cpanel::Exception::IO::LinkError;

# cpanel - Cpanel/Exception/IO/LinkError.pm        Copyright 2022 cPanel, L.L.C.
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
        'The system failed to create a hard link “[_1]” to “[_2]” because of an error: [_3]',
        ( map { $self->get($_) } qw( newpath oldpath error ) ),
    );
}

1;
