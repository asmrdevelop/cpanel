package Cpanel::iContact::Class::Check::HostnameOwnedByUser;

# cpanel - Cpanel/iContact/Class/Check/HostnameOwnedByUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my $WHM_CHANGE_HOSTNAME = 'scripts2/changehostname';

my @args = qw(
  user
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

    my %template_args = (
        $self->SUPER::_template_args(),
        'whm_change_hostname_url' => $self->_get_whm_login_url() . $WHM_CHANGE_HOSTNAME,
        'cpanel_login_url'        => $self->_get_cpanel_login_url(),
        map { $_ => $self->{'_opts'}{$_} } (@args),
    );

    return %template_args;
}

sub _get_whm_login_url {
    my ($self) = @_;
    return $self->assemble_whm_url('');
}

sub _get_cpanel_login_url {
    my ($self) = @_;
    return $self->assemble_cpanel_url('');
}

1;
