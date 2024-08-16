package Cpanel::iContact::Class::wwwacct::Notify;

# cpanel - Cpanel/iContact/Class/wwwacct/Notify.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @args = (
    qw(
      user_domain
      ip
      useip
      has_cgi
      user
      password
      cpanel_mod
      home_root
      quota
      nameservers
      contact_email
      cpanel_package
      feature_list
      locale
      env_remote_user
      env_user
      host_server
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
