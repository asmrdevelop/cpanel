package Cpanel::Server::Type::Role::FileStorage::Change;

# cpanel - Cpanel/Server/Type/Role/FileStorage/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::FileStorage::Change - Enable and disable logic for file storage services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::FileStorage::Change;

    my $role = Cpanel::Server::Type::Role::FileStorage::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls file storage services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::FileStorage ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::FileStorage::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::FileStorage::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable File Storage
}

sub _disable {

    # TODO: Actually disable File Storage
}

1;
