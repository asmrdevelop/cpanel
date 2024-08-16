package Cpanel::iContact::Class::cPHulk::Login;

# cpanel - Cpanel/iContact/Class/cPHulk/Login.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = (
    'user',
    'user_domain',
    'report',
    'is_root',
    'is_local',
    'whitelist_ips',
    'blacklist_ips',
    'known_netblock',
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _icontact_args {
    my ($self) = @_;

    my @args = (
        $self->SUPER::_icontact_args(),

        #TODO: Give customers control over this string.
        from => 'cPanel Login Notification',
    );

    return @args;
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } @required_args,
    );
}

1;
