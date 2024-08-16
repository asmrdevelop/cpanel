package Cpanel::iContact::Class::PHPFPM::AccountOverquota;

# cpanel - Cpanel/iContact/Class/PHPFPM/AccountOverquota.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::iContact::Class::PHPFPM::AccountOverquota - Module for notifying when
an account is overquota and preventing PHP-FPM from starting up.

=head1 SYNOPSIS

 Cpanel::iContact::Class::PHPFPM::AccountOverquota->new(
        origin   => '/usr/local/cpanel/scripts/restartsrv_apache_php_fpm',
        user       => 'cptest99',
        domain     => 'cptest99.tld',
        conf_file  => '/etc/cpanel/ea-php99/root/etc/php-fpm.d/mydomain.conf',
        moved_file => '/etc/cpanel/ea-php99/root/etc/php-fpm.d/mydomain.conf.moved',
 );

=head1 DESCRIPTION

Module for notifying when an account is overquota and is preventing the startup
of the PHP-FPM daemon.

=cut

use parent qw(
  Cpanel::iContact::Class
);

my @required_args = qw(
  user
  domain
  conf_file
  moved_file
);

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

        map { $_ => $self->{'_opts'}{$_} } qw(
          user
          domain
          conf_file
          moved_file
        )
    );
}

1;
