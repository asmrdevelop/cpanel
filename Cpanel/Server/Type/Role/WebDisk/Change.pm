package Cpanel::Server::Type::Role::WebDisk::Change;

# cpanel - Cpanel/Server/Type/Role/WebDisk/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::WebDisk::Change - Enable and disable logic for web disk services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::WebDisk::Change;

    my $role = Cpanel::Server::Type::Role::WebDisk::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls web disk services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::WebDisk ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::WebDisk::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::WebDisk::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable Web Disk
}

sub _disable {

    # TODO: Actually disable Web Disk
}

1;
