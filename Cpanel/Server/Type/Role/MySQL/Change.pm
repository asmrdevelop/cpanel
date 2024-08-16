package Cpanel::Server::Type::Role::MySQL::Change;

# cpanel - Cpanel/Server/Type/Role/MySQL/Change.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MySQL::Change - Enable and disable logic for MySQL services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::MySQL::Change;

    my $role = Cpanel::Server::Type::Role::MySQL::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls MySQL services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::MySQL ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::MySQL::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::MySQL::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable MySQL
}

sub _disable {

    # TODO: Actually disable MySQL
}

1;
