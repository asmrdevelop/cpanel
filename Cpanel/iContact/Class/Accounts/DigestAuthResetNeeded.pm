package Cpanel::iContact::Class::Accounts::DigestAuthResetNeeded;

# cpanel - Cpanel/iContact/Class/Accounts/DigestAuthResetNeeded.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @args = (
    qw(
      username
      old_domain
      new_domain
      digest_disabled_users
    )
);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @args,
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } @args
    );
}

1;
