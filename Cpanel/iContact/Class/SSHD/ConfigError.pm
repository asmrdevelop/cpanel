package Cpanel::iContact::Class::SSHD::ConfigError;

# cpanel - Cpanel/iContact/Class/SSHD/ConfigError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Cpanel::iContact::Class
);

=head1 NAME

Cpanel::iContact::Class::SSHD::ConfigError

=head1 DESCRIPTION

This module provides notifications for SSHD configuration change failures.
It is used indirectly through the Cpanel::Notify system.

=head1 SYNOPSIS

  use Cpanel::Notify;

  Cpanel::Notify::notification_class(
      'class'            => 'SSHD::ConfigError',
      'application'      => 'Install::SSHD',
      'constructor_args' => [
          syntax_error => "syntax error in conf change",
          diff         => "diff -u output",
          filename     => "/etc/ssh/sshd_config",
      ]
  );

=cut

sub _template_args {
    my ($self) = @_;

    return (
        $self->SUPER::_template_args(),
        map { $_ => $self->{'_opts'}{$_} } (qw{filename diff syntax_error})
    );
}

1;
