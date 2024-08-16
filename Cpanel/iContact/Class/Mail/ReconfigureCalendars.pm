package Cpanel::iContact::Class::Mail::ReconfigureCalendars;

# cpanel - Cpanel/iContact/Class/Mail/ReconfigureCalendars.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  account
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } (@required_args)
    );
}

=pod

Notification class for the one-time change that end-users of CalDAV/CardDAV services
must make in their clients after the upgrade from CCS to cpdavd-based connections.

=cut

1;
