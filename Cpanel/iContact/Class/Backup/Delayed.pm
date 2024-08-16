package Cpanel::iContact::Class::Backup::Delayed;

# cpanel - Cpanel/iContact/Class/Backup/Delayed.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw();

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        %{ $self->_get_system_info_template_vars() },
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
