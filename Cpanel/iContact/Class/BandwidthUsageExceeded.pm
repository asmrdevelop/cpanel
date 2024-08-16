package Cpanel::iContact::Class::BandwidthUsageExceeded;

# cpanel - Cpanel/iContact/Class/BandwidthUsageExceeded.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = (
    qw(
      user
      user_domain
      warn
      warnpercent
      bwused
      bwlimit
    )
);

sub priority { return 1 }

sub _TEMPLATE_ARGS_LIST {
    return;
}

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

        map { $_ => $self->{'_opts'}{$_} } (
            qw(
              avg_bw_usage
              predicted_bw
              date_exceeded
            ), @required_args
        )
    );
}

1;
