package Cpanel::Server::Type::Role::DNS::Change;

# cpanel - Cpanel/Server/Type/Role/DNS/Change.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::DNS::Change - Enable and disable logic for the DNS role

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::DNS::Change;

    my $role = Cpanel::Server::Type::Role::DNS::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls DNS services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::DNS ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::DNS::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::DNS::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable DNS
}

sub _disable {

    # TODO: Actually disable DNS
}

1;
