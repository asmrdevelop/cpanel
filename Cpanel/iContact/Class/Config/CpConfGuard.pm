package Cpanel::iContact::Class::Config::CpConfGuard;

# cpanel - Cpanel/iContact/Class/Config/CpConfGuard.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::ConfigFiles ();

my @args = qw(critical_values origin);

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
        'cpanel_config_path'         => $Cpanel::ConfigFiles::cpanel_config_file,
        'default_cpanel_config_path' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/etc/cpanel.config',
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
