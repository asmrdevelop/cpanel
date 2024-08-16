package Cpanel::Server::Type::Role::WebDisk;

# cpanel - Cpanel/Server/Type/Role/WebDisk.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::WebDisk - Web disk role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::WebDisk;

    my $role = Cpanel::Server::Type::Role::WebDisk->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls web disk services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/webdisk";
our $SERVICES  = [qw(cpdavd)];

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("[asis,Web Disk]");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("[asis,Web Disk] allows users to manage and manipulate files on the server with multiple types of devices.");
    return $DESCRIPTION;
}

sub _TOUCHFILE { return $TOUCHFILE; }

=head2 SERVICES

Gets the list of services that are needed to fulfil the role

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an C<ARRAYREF> of strings representing the services that the role needs

=back

=back

=cut

sub SERVICES { return $SERVICES; }

=head2 RESTART_SERVICES

Gets the list of services that need to be restarted when this role is enabled or disabled

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<ARRAYREF>

Returns an C<ARRAYREF> of strings representing the services that need to be restarted

=back

=back

=cut

sub RESTART_SERVICES { return $SERVICES; }

#----------------------------------------------------------------------

use constant _SERVICE_SUBDOMAINS => ['webdisk'];

1;
