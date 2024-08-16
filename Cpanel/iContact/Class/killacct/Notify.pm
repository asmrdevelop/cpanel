package Cpanel::iContact::Class::killacct::Notify;

# cpanel - Cpanel/iContact/Class/killacct/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @args = (
    qw(
      account_owner
      user
      user_domain
      host
      env_remote_user
      env_user
    )

);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
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
