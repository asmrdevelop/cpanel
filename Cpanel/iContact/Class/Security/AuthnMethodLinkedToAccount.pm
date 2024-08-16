package Cpanel::iContact::Class::Security::AuthnMethodLinkedToAccount;

# cpanel - Cpanel/iContact/Class/Security/AuthnMethodLinkedToAccount.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class::FromUserAction
);

my @required_args = qw(username user user_domain provider_display_name preferred_username);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args
    );
}

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),

        map { $_ => $self->{'_opts'}{$_} } (@required_args)
    );
}

1;
