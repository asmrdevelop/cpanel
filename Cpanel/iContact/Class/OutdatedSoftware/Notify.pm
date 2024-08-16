package Cpanel::iContact::Class::OutdatedSoftware::Notify;

# cpanel - Cpanel/iContact/Class/OutdatedSoftware/Notify.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

my @args          = qw(origin outdated_software);
my @optional_args = qw(update_required);

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
        map { $_ => $self->{'_opts'}{$_} } ( @args, @optional_args ),
    );

    return %template_args;
}

1;
