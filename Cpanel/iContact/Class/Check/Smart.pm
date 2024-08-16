package Cpanel::iContact::Class::Check::Smart;

# cpanel - Cpanel/iContact/Class/Check/Smart.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  origin
  attach_files
);

my @template_args = (@required_args);

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
        'disable_smartcheck_touchfile' => '/var/cpanel/disablesmartcheck',
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

1;
