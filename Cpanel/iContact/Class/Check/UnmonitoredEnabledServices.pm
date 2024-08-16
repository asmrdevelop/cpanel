package Cpanel::iContact::Class::Check::UnmonitoredEnabledServices;

# cpanel - Cpanel/iContact/Class/Check/UnmonitoredEnabledServices.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw(origin services);

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
        'service_manager_url'                         => $self->assemble_whm_url('scripts/srvmng'),
        'enable_monitor_all_enabled_services_command' => '/usr/local/cpanel/bin/whmapi1 enable_monitor_all_enabled_services',
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
