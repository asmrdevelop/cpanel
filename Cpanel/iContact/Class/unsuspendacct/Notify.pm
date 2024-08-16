package Cpanel::iContact::Class::unsuspendacct::Notify;

# cpanel - Cpanel/iContact/Class/unsuspendacct/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = (
    'user',
    'user_domain',
    'host_server',
    'env_remote_user',
    'env_user'
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } @required_args
    );
}

1;
