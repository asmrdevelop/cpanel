package Cpanel::iContact::Class::DemoMode::MailChildNodeExists;

# cpanel - Cpanel/iContact/Class/DemoMode/MailChildNodeExists.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  affected_users
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

        map { $_ => $self->{'_opts'}{$_} } @required_args
    );
}

1;

__END__

=head1 NAME

Cpanel::iContact::Class::DemoMode::MailChildNodeExists

=head1 DESCRIPTION

This notification should be used when a mail child
node is configured with a Demo Mode account during an upgrade.
This causes the child node account to not have the same demo
mode restrictions as the parent.

=cut


