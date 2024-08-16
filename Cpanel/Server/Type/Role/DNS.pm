package Cpanel::Server::Type::Role::DNS;

# cpanel - Cpanel/Server/Type/Role/DNS.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::DNS - DNS role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::DNS;

    my $role = Cpanel::Server::Type::Role::DNS->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls DNS services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/dns";

# dnsadmin currently cannot be disabled.  In a later phase
# we may add it to this list.
our $SERVICES = [
    'named',
    'bind',
    'nsd',
    'pdns',
    'powerdns',
];

sub _NAME {
    _require_localestring();
    $NAME ||= Cpanel::LocaleString->new("[asis,DNS]");    # PPI NO PARSE - hide from cplint
    return $NAME;
}

sub _DESCRIPTION {
    _require_localestring();
    $DESCRIPTION ||= Cpanel::LocaleString->new("[asis,DNS] allows users to create and edit Domain Name System zone files.");    # PPI NO PARSE - hide from cplint
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

# BIND remains installed regardless of whether it’s the active nameserver.
use constant _RPM_TARGETS => [
    'powerdns',
];

#----------------------------------------------------------------------

# This works around CPANEL-31033:
sub _require_localestring {
    my $relpath = 'Cpanel/LocaleString.pm';
    require $relpath;

    return;
}

1;
