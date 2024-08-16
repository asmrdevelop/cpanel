package Cpanel::iContact::Class::Check::CpanelPackages;

# cpanel - Cpanel/iContact/Class/Check/CpanelPackages.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

use Cpanel::ConfigFiles ();

my @args = qw(origin rpms);

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
        'check_cpanel_pkgs_path' => $Cpanel::ConfigFiles::CPANEL_ROOT . '/scripts/check_cpanel_pkgs',
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
