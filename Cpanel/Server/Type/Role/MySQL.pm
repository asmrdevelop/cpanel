package Cpanel::Server::Type::Role::MySQL;

# cpanel - Cpanel/Server/Type/Role/MySQL.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MySQL - MySQL role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::MySQL;

    my $role = Cpanel::Server::Type::Role::MySQL->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls MySQL services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/mysql";
our $SERVICES  = [qw(mysql)];

sub _NAME {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    $NAME ||= 'Cpanel::LocaleString'->new("[asis,MySQL]/[asis,MariaDB]");
    return $NAME;
}

sub _DESCRIPTION {
    eval 'require Cpanel::LocaleString' or die;    ## no critic qw(ProhibitStringyEval)
    $DESCRIPTION ||= 'Cpanel::LocaleString'->new("This role controls the local [asis,MySQL]/[asis,MariaDB] service.");
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

1;
