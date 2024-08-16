package Cpanel::iContact::Class::cPHulk::BruteForce;

# cpanel - Cpanel/iContact/Class/cPHulk/BruteForce.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = (
    'user',
    'current_failures',
    'max_allowed_failures',
    'report',
    'whitelist_ips',
    'blacklist_ips'
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

        from => 'cPanel Hulk Brute Force Protection',
    );

    return @args;
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, 'host_server' )
    );
}

1;
