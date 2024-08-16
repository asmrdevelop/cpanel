package Cpanel::Server::Type::Role::Webmail;

# cpanel - Cpanel/Server/Type/Role/Webmail.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::Webmail - Webmail role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::Webmail;

    my $role = Cpanel::Server::Type::Role::Webmail->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls webmail services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );

our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/webmail";

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("Webmail");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("Webmail provides access to webmail services.");
    return $DESCRIPTION;
}

sub _TOUCHFILE { return $TOUCHFILE; }

use constant _SERVICE_SUBDOMAINS => ['webmail'];

1;
