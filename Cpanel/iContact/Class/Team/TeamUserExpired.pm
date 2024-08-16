package Cpanel::iContact::Class::Team::TeamUserExpired;

# cpanel - Cpanel/iContact/Class/Team/TeamUserExpired.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(
  user
  username
  team_user
);
my @optional_args = qw(
  task_error
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
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args )
    );
}

1;
