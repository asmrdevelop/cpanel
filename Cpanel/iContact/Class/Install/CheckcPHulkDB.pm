package Cpanel::iContact::Class::Install::CheckcPHulkDB;

# cpanel - Cpanel/iContact/Class/Install/CheckcPHulkDB.pm
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

Cpanel::iContact::Class::Install::CheckcPHulkDB

=head1 DESCRIPTION

This notification is used whenever a corrupt cPHulk DB is detected on the system by the
L<Install::CheckcPHulkDB> task.

=cut

my @args = qw(rebuild_details);

sub _required_args {
    my ($self) = @_;

    return (
        $self->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args,
    );
}

1;
