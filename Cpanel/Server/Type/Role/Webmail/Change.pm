package Cpanel::Server::Type::Role::Webmail::Change;

# cpanel - Cpanel/Server/Type/Role/Webmail/Change.pm
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::Webmail::Change - Enable and disable logic for webmail services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::Webmail::Change;

    my $role = Cpanel::Server::Type::Role::Webmail::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls webmail services and features

=head1 SUBROUTINES

=cut

use cPstrict;

use Cpanel::Server::Type::Role::Webmail ();
use Cpanel::RPM::Versions::Target       ();

use parent 'Cpanel::Server::Type::Role::TouchFileRole::Change';

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::Webmail::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::Webmail::_TOUCHFILE;
}

sub _enable {
    Cpanel::RPM::Versions::Target::restore_to_defaults('roundcube');
    return 1;
}

sub _disable {
    Cpanel::RPM::Versions::Target::set( 'roundcube' => 'uninstalled' );
    return 1;
}

1;
