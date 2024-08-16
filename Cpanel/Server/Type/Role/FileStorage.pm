package Cpanel::Server::Type::Role::FileStorage;

# cpanel - Cpanel/Server/Type/Role/FileStorage.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::FileStorage - File storage role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::FileStorage;

    my $role = Cpanel::Server::Type::Role::FileStorage->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls file storage services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/filestorage";

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("File Storage");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("File Storage allows users to access the File Manager and Git™ Version Control features.");
    return $DESCRIPTION;
}

sub _TOUCHFILE { return $TOUCHFILE; }

1;
