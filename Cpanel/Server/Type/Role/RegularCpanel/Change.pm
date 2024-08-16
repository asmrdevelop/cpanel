package Cpanel::Server::Type::Role::RegularCpanel::Change;

# cpanel - Cpanel/Server/Type/Role/RegularCpanel/Change.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::RegularCpanel::Change - Enable and disable logic for RegularCpanel role.

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::RegularCpanel::Change;

    my $role = Cpanel::Server::Type::Role::RegularCpanel::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls RegularCpanel features.

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::RegularCpanel ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::RegularCpanel::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::RegularCpanel::_TOUCHFILE;
}

sub _enable {

    # nothing special to do
    return;
}

sub _disable {

    # nothing special to do
    return;
}

1;
