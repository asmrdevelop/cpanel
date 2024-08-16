package Cpanel::iContact::Class::Mail::SendLimitExceeded;

# cpanel - Cpanel/iContact/Class/Mail/SendLimitExceeded.pm
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
  domain
  user
  threshold
);

my @optional_args = qw(
  limit_type
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

__END__

=pod

=head1 NAME

Cpanel::iContact::Class::Mail::SendLimitExceeded

=head1 DESCRIPTION

This notification should be used when a mail domain has exceeded the number of sends in a 24-hour
period specified in tweak setting emailsperdaynotify.

=cut
