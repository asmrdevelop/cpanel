package Cpanel::Exception::IO::EUIDMismatch;

# cpanel - Cpanel/Exception/IO/EUIDMismatch.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Cpanel::LocaleString ();

#Metadata propreties:
#   path    - can be an arrayref
sub _default_phrase {
    my ($self) = @_;

    my $path = $self->{_metadata}{path};
    $path = [$path] if !ref $path;

    return Cpanel::LocaleString->new( "The [asis,EUID], [_1], does not own [list_or,_2].", $>, $path );
}

1;
