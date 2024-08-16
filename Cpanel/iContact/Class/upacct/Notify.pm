package Cpanel::iContact::Class::upacct::Notify;

# cpanel - Cpanel/iContact/Class/upacct/Notify.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @args = (
    qw(
      user
      user_domain
      ip
      new_plan
      old_plan
      host
      env_remote_user
      env_user
    )

);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args
    );
}

sub _icontact_args {
    my ($self) = @_;

    return $self->SUPER::_icontact_args() if !$self->{'_opts'}{'to'};

    return (
        $self->SUPER::_icontact_args(),
        to => $self->{'_opts'}{'to'},
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args
    );
}

1;
