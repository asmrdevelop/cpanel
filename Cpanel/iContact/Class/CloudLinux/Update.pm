package Cpanel::iContact::Class::CloudLinux::Update;

# cpanel - Cpanel/iContact/Class/CloudLinux/Update.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @args = qw(hostname);

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
        'cloudlinux_install_command' => 'curl -s -L https://repo.cloudlinux.com/cloudlinux/sources/cln/cldeploy | sh',
        map { $_ => $self->{'_opts'}{$_} } (@args),
    );

    return %template_args;
}

1;
