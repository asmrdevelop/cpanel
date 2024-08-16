package Cpanel::iContact::Class::OverLoad::CpuWatch;

# cpanel - Cpanel/iContact/Class/OverLoad/CpuWatch.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::iContact::Utils ();

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        %{ $self->_get_system_info_template_vars() },
        procdata => scalar Cpanel::iContact::Utils::procdata_for_template_sorted_by_cpu( $self->_get_procdata_for_template() ),
        ( map { $_ => $self->{'_opts'}{$_} } $self->_TEMPLATE_ARGS_LIST() ),
    );
}

sub _required_args {
    my ($class) = @_;

    return (
        $class->_TEMPLATE_ARGS_LIST(),
    );
}

sub _TEMPLATE_ARGS_LIST {
    my ($self) = @_;

    return (
        'user',
        'cpu',
        'mem',
        'command',
        'pid',
        'elapsed'
    );
}

1;
