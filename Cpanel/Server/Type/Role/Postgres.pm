package Cpanel::Server::Type::Role::Postgres;

# cpanel - Cpanel/Server/Type/Role/Postgres.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::Postgres - Postgres role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::Postgres;

    my $role = Cpanel::Server::Type::Role::Postgres->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls Postgres services and features.

Note that this role’s availability (i.e., C<is_available()>) depends on
whether cPanel manages a PostgreSQL installation on the server.

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

use Cpanel::GlobalCache ();

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/postgres";
our $SERVICES  = [qw(postgresql)];

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("[asis,PostgreSQL]");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("[asis,PostgreSQL] allows users to create and manage [asis,PostgreSQL] databases.");
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

#----------------------------------------------------------------------

sub _is_available {
    return !!Cpanel::GlobalCache::data( 'cpanel', 'has_postgres' );
}

1;
