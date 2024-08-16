package Cpanel::iContact::Class::Check::IP;

# cpanel - Cpanel/iContact/Class/Check/IP.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  origin
  problems
);

my @template_args = (
    @required_args,
    qw(
      right_ip
      wrong_ip
    )
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
        'etc_hosts_path'   => '/etc/hosts',
        'resolv_conf_path' => '/etc/resolv.conf',
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

1;
