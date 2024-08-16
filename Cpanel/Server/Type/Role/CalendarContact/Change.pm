package Cpanel::Server::Type::Role::CalendarContact::Change;

# cpanel - Cpanel/Server/Type/Role/CalendarContact/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::CalendarContact::Change - Enable and disable logic for CalDAV and CardDAV services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::CalendarContact::Change;

    my $role = Cpanel::Server::Type::Role::CalendarContact::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls CalDAV and CardDAV services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::CalendarContact ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::CalendarContact::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::CalendarContact::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable CalendarContact
}

sub _disable {

    # TODO: Actually disable CalendarContact
}

1;
