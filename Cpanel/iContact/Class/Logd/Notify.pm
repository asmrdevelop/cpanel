package Cpanel::iContact::Class::Logd::Notify;

# cpanel - Cpanel/iContact/Class/Logd/Notify.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::ConfigFiles::Apache ();

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  origin
  bandwidth_type
  cpanel_error_log_path
  cpanel_stats_log_path
  user
  user_domain
);

#if we detect a suspicious user we only pass that, otherwise if we fail to create a directory we pass a reason
my @template_args = (
    @required_args,
);

sub new {
    my ( $class, %args ) = @_;

    return $class->SUPER::new(
        %args,
    );
}

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
        %{ $self->_get_system_info_template_vars() },
        map { $_ => $self->{'_opts'}{$_} } (@template_args),
    );
}

1;
