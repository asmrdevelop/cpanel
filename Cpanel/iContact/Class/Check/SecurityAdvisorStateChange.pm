package Cpanel::iContact::Class::Check::SecurityAdvisorStateChange;

# cpanel - Cpanel/iContact/Class/Check/SecurityAdvisorStateChange.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw(origin notices highest_notice_type);

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
        'security_advisor_url' => $self->assemble_whm_url('cgi/securityadvisor/index.cgi'),
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
