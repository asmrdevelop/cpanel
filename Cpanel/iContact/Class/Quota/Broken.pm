package Cpanel::iContact::Class::Quota::Broken;

# cpanel - Cpanel/iContact/Class/Quota/Broken.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

sub _RELATIVE_TEMPLATE_PATH {
    my ( $self, $type ) = @_;

    my $name = $self->_NAME();

    return "Quota/$name.$type.tmpl";
}

1;
