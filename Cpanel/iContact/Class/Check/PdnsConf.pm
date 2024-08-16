package Cpanel::iContact::Class::Check::PdnsConf;

# cpanel - Cpanel/iContact/Class/Check/PdnsConf.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

=head1 NAME

Cpanel::iContact::Class::Check::PdnsConf

=head1 DESCRIPTION

This notification is used whenever the PowerDNS configuration is altered by the
C<migrate-pdns-conf> script to update directives from pre-v4.1 to v4.1.

=cut

my @args = qw(origin removed renamed manual enabled);

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
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
