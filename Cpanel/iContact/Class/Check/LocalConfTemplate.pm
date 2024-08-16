package Cpanel::iContact::Class::Check::LocalConfTemplate;

# cpanel - Cpanel/iContact/Class/Check/LocalConfTemplate Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Cpanel::iContact::Class
);

=head1 NAME

Cpanel::iContact::Class::Check::LocalConfTemplate

=head1 DESCRIPTION

This notification is used whenever a configuration template is updated and
a local configuration template is in use.

It is meant to notify admins that their local changes may need to be updated
continue working.

=cut

my @args = qw(origin service template errors);

sub _required_args ($class) {
    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args ($self) {
    my %template_args = (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args,
    );

    return %template_args;
}

1;
