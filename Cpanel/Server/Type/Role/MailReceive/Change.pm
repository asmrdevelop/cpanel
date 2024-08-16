package Cpanel::Server::Type::Role::MailReceive::Change;

# cpanel - Cpanel/Server/Type/Role/MailReceive/Change.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MailReceive::Change - Enable and disable logic for mail services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::MailReceive::Change;

    my $role = Cpanel::Server::Type::Role::MailReceive::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls mail services and features

=head1 SUBROUTINES

=cut

use cPstrict;

use Cpanel::Server::Type::Role::MailReceive ();
use Cpanel::RPM::Versions::Target           ();

use parent 'Cpanel::Server::Type::Role::TouchFileRole::Change';

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::MailReceive::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::MailReceive::_TOUCHFILE;
}

sub _enable {
    Cpanel::RPM::Versions::Target::restore_to_defaults('mailman');
    return 1;
}

sub _disable {
    Cpanel::RPM::Versions::Target::set( 'mailman' => 'uninstalled' );
    return 1;
}

1;
