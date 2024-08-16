package Cpanel::Server::Type::Role::MailRelay::Change;

# cpanel - Cpanel/Server/Type/Role/MailRelay/Change.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MailRelay::Change - Enable and disable logic
for mail relaying

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::MailRelay::Change;

    my $role = Cpanel::Server::Type::Role::MailRelay::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls mail
services and features

=head1 SUBROUTINES

=cut

use Cpanel::Server::Type::Role::MailRelay ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::MailRelay::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::MailRelay::_TOUCHFILE;
}

sub _enable {

    # TODO: Actually re-enable MailRelay
}

sub _disable {

    # TODO: Actually disable MailRelay
}

1;
