package Cpanel::iContact::Class::EasyApache::EA4_ConflictRemove;

# cpanel - Cpanel/iContact/Class/EasyApache/EA4_ConflictRemove.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=head1 NAME

Cpanel::iContact::Class::EasyApache::EA4_ConflictRemove

=head1 DESCRIPTION

This notification should be used when any script attempts to resolve a conflict between two packages in EasyApache 4.

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

my @args = qw( tried_to_keep tried_to_remove failed_to_remove );

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
        map { $_ => $self->{'_opts'}{$_} } @args
    );

    return %template_args;
}

1;
