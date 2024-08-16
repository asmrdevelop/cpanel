package Cpanel::iContact::Class::ChangePassword::NewUser;

# cpanel - Cpanel/iContact/Class/ChangePassword/NewUser.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(
  user
  user_domain
  username
  cookie
  team_account
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
    my $account_type = $self->{'_opts'}{team_account} ? '&account_type=team_user' : '';
    return (
        $self->SUPER::_template_args(),
        'change_password_url' => $self->assemble_cpanel_url( 'invitation?user=' . $self->{'_opts'}{user} . '&cookie=' . $self->{'_opts'}{cookie} . $account_type ),

        map { $_ => $self->{'_opts'}{$_} } @required_args,
    );
}

1;
