package Cpanel::iContact::Class::Install::SwitchtoPowerDNS;

# cpanel - Cpanel/iContact/Class/Install/SwitchtoPowerDNS.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

=head1 NAME

Cpanel::iContact::Class::Install::SwitchtoPowerDNS

=head1 DESCRIPTION

This notification is used when the name server is changed by the
L<Install::SwitchtoPowerDNS> task.

=cut

sub _required_args {
    my ($self) = @_;

    return (
        $self->SUPER::_required_args(),
        'old_nameserver',
        'new_nameserver',
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } (
            'origin',
            'old_nameserver',
            'new_nameserver',
        )
    );
}

1;
