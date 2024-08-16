package Cpanel::iContact::Class::Logger::Notify;

# cpanel - Cpanel/iContact/Class/Logger/Notify.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my $locale;
my @required_args = qw(origin attach_files logger_call);
my @optional_args = qw(subject);

sub _required_args {
    my ($class) = @_;

    return (
        $class->SUPER::_required_args(),
        @required_args,
    );
}

sub _template_args {
    my ($self) = @_;

    my %template_args = (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } ( @required_args, @optional_args ),
    );

    return %template_args;
}

1;
