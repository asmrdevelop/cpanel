package Cpanel::iContact::Class::Install::CheckRemoteMySQLVersion;

# cpanel - Cpanel/iContact/Class/Install/CheckRemoteMySQLVersion.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

sub _required_args {
    my ($self) = @_;

    return (
        $self->SUPER::_required_args(),
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } (
            'origin',
            'current_version',
        )
    );
}

1;
