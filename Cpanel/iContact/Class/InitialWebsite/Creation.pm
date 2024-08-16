package Cpanel::iContact::Class::InitialWebsite::Creation;

# cpanel - Cpanel/iContact/Class/InitialWebsite/Creation.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

=head1 NAME

Cpanel::iContact::Class::InitialWebsite::Creation

=head1 IMPLEMENTATION OF REQUIRED INTERFACE

=head2 Parent class

Cpanel::iContact::Class::FromUserAction

=head2 _required_args()

Required arguments. Do not call this directly.

=cut

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        'username',
        'domain',
        'status',
        'reason',
        'login_url',
    );
}

=head2 _required_args()

Template argument. Do not call this directly.

=cut

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        username  => $self->{'_opts'}{'username'},
        domain    => $self->{'_opts'}{'domain'},
        status    => $self->{'_opts'}{'status'},
        reason    => $self->{'_opts'}{'reason'},
        login_url => $self->{'_opts'}{'login_url'},
    );
}

1;
