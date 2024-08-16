package Cpanel::Exception::IO::UnlinkError;

# cpanel - Cpanel/Exception/IO/UnlinkError.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   path    (can be an arrayref)
#   error
sub _default_phrase {
    my ($self) = @_;

    my $path_ar = $self->get('path');

    $path_ar = [$path_ar] if !ref $path_ar;

    return Cpanel::LocaleString->new(
        'The system failed to unlink [list_and_quoted,_1] because of an error: [_2]',
        $path_ar,
        $self->get('error'),
    );
}

1;
