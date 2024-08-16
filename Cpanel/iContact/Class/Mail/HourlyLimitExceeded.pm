package Cpanel::iContact::Class::Mail::HourlyLimitExceeded;

# cpanel - Cpanel/iContact/Class/Mail/HourlyLimitExceeded.pm
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
  limit_type
);

my @optional_args = qw();

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

=head1 NAME

Cpanel::iContact::Class::Mail::HourlyLimitExceeded

=head1 DESCRIPTION

This notification should be used when a mail domain exceeds the
number of sends in a one-hour period specified in Tweak Setting
maxemailsperhour.

=cut
