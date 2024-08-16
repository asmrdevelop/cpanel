package Cpanel::Template::Plugin::ServerRoles;

# cpanel - Cpanel/Template/Plugin/ServerRoles.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::ServerRoles - Template Toolkit plugin for server roles

=head1 SYNOPSIS

    [% use ServerRoles %]

    [% IF ServerRoles.is_role_enabled('RoleModuleName') %]
        [%# Do something when the role is enabled %]
    [% END %]

=cut

use parent 'Template::Plugin';

use Cpanel::Server::Type::Role::MailReceive     ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::CalendarContact ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::FTP             ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::DNS             ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::MailLocal       ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::MailSend        ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::WebServer       ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Server::Type::Role::WebDisk         ();    # PPI USE OK - will be loaded anyways so faster to perlcc
use Cpanel::Services::Installed                 ();    # PPI USE OK - will be loaded anyways so faster to perlcc

=head2 new

Constructor

=over 2

=item Input

=over 3

None

=back

=item Output

=over 3

=item C<SCALAR>

A new C<Cpanel::Template::Plugin::ServerRoles> object

=back

=back

=cut

sub new {
    return bless {}, $_[0];
}

=head2 is_role_enabled

Determines if a role is enabled on the server

=over 2

=item Input

=over 3

=item C<SCALAR>

The name of the role module to check for enabled/disabled

=back

=item Output

=over 3

Returns 1 if the role is enabled, 0 otherwise

=back

=back

=cut

sub is_role_enabled {
    my ( $self, $role ) = @_;
    require Cpanel::Server::Type::Profile::Roles;
    return Cpanel::Server::Type::Profile::Roles::is_role_enabled($role);
}

=head2 are_roles_enabled

Determines if the specified roles are enabled on the server

=over 2

=item Input

=over 3

This method is a thin wrapper around C<Cpanel::Server::Type::Profile::Roles::are_roles_enabled>, see that module for specifics on accepted inputs

=back

=item Output

=over 3

Outputs 1 if the roles are enabled, 0 otherwise

=back

=back

=cut

sub are_roles_enabled {
    my ( $self, $roles ) = @_;
    require Cpanel::Server::Type::Profile::Roles;
    return Cpanel::Server::Type::Profile::Roles::are_roles_enabled($roles);
}

1;
