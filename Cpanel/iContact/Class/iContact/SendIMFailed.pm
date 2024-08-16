package Cpanel::iContact::Class::iContact::SendIMFailed;

# cpanel - Cpanel/iContact/Class/iContact/SendIMFailed.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(
  error
  original_message
  original_subject
  original_recipient
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
        map { $_ => $self->{'_opts'}{$_} } (@template_args)
    );
}

sub _icontact_args {
    my ($self) = @_;
    return (
        $self->SUPER::_icontact_args(),
        'email_only' => 1,
    );
}

1;
