package Cpanel::iContact::Class::Backup::Disabled;

# cpanel - Cpanel/iContact/Class/Backup/Disabled.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::LoadModule ();

sub new {
    my ( $class, %args ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Hostname');

    return $class->SUPER::new(
        %args,
        host_server => Cpanel::Hostname::gethostname(),
    );
}

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'origin',
        'name',
        'type',
        'remote_host',
        'reason',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } qw(
          origin
          name
          type
          remote_host
          reason
          host_server
        )
    );
}

1;
