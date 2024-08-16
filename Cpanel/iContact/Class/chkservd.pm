package Cpanel::iContact::Class::chkservd;

# cpanel - Cpanel/iContact/Class/chkservd.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

sub priority { return 1 }

sub _TEMPLATE_ARGS_LIST {
    return;
}

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        $class->_TEMPLATE_ARGS_LIST(),
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        %{ $self->_get_system_info_template_vars() },
        ( map { $_ => $self->{'_opts'}{$_} } $self->_TEMPLATE_ARGS_LIST() ),
    );
}

sub _icontact_args {
    my ($self) = @_;

    my @args = (
        $self->SUPER::_icontact_args(),

        #TODO: Give customers control over this string.
        from => 'cPanel Monitoring',
    );

    return @args;
}

1;
