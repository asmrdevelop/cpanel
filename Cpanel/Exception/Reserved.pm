package Cpanel::Exception::Reserved;

# cpanel - Cpanel/Exception/Reserved.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::InvalidParameter );

use Cpanel::LocaleString ();

sub _default_phrase {
    my ($self) = @_;

    return Cpanel::LocaleString->new(
        '“[_1]” is a reserved value.',
        $self->{'_metadata'}{'value'},
    );
}

1;
