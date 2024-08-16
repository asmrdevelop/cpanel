package Cpanel::Server::Type::Role::FTP::Change;

# cpanel - Cpanel/Server/Type/Role/FTP/Change.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::FTP::Change - Enable and disable logic for FTP services and features

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::FTP::Change;

    my $role = Cpanel::Server::Type::Role::FTP::Change->new();
    $role->enable();
    $role->disable();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role::Change> that controls FTP services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use Cpanel::Server::Type::Role::FTP ();

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole::Change
);

BEGIN {
    *_NAME      = *Cpanel::Server::Type::Role::FTP::_NAME;
    *_TOUCHFILE = *Cpanel::Server::Type::Role::FTP::_TOUCHFILE;
}

sub _enable {

    my ($self) = @_;

    # Perform no action when enabling the FTP role.
    #
    # FTP is no longer enabled on fresh installs. So we will not enable it
    # when switching profiles. Users can still install an FTP server from the
    # WHM UI or /scripts/setupftpserver when using the Standard profile.

    return;
}

sub _disable {

    my ($self) = @_;

    require Whostmgr::ServiceSwitch::ftpserver;
    Whostmgr::ServiceSwitch::ftpserver::switch( 'ftpserver' => 'disabled' );

    return;
}

1;
