package Cpanel::Server::Type::Role::RegularCpanel;

# cpanel - Cpanel/Server/Type/Role/RegularCpanel.pm
#                                                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::RegularCpanel - RegularCpanel role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::RegularCpanel;

    my $role = Cpanel::Server::Type::Role::RegularCpanel->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls a Regular Cpanel installation.
This is a placeholders for features that only makes sense for selling the regular cPanel
product.

=head1 SUBROUTINES

=cut

use cPstrict;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/regularcpanel";

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    state $NAME = Cpanel::LocaleString->new("RegularCpanel");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    state $DESCRIPTION = Cpanel::LocaleString->new("RegularCpanel provides access to standard cPanel features.");
    return $DESCRIPTION;
}

sub _TOUCHFILE { return $TOUCHFILE; }

1;
