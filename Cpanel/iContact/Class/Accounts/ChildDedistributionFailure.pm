package Cpanel::iContact::Class::Accounts::ChildDedistributionFailure;

# cpanel - Cpanel/iContact/Class/Accounts/ChildDedistributionFailure.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  user
  worker_type
);

my @optional_args = qw(
  distribution_errors
);

sub _required_args ($class) {

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args ($self) {

    return (
        $self->SUPER::_template_args(),

        ( map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args ) ),
        'linked_nodes_whm_url' => $self->assemble_whm_url('scripts7/link-server-nodes'),
    );
}

1;

__END__

=head1 NAME

Cpanel::iContact::Class::Accounts::ChildDedistributionFailure

=head1 DESCRIPTION

This notification should be used when de-distributing an account's mail
and there is a failure.

=cut
