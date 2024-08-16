package Cpanel::Server::Type::Role::SpamFilter;

# cpanel - Cpanel/Server/Type/Role/SpamFilter.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::SpamFilter - SpamFilter role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::SpamFilter;

    my $role = Cpanel::Server::Type::Role::SpamFilter->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls SpamFilter services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );
our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/spamfilter";
our $SERVICES  = [qw(spamd)];

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("[asis,Spam] Filter");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("[asis,Spam] Filter allows users to use [asis,Apache SpamAssassin™] to identify, sort, and delete unsolicited mail.");
    return $DESCRIPTION;
}

sub _TOUCHFILE { return $TOUCHFILE; }

=head2 SERVICES

Gets the list of services that are needed to fulfill the role

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
