package Cpanel::Server::Type::Role::MailReceive;

# cpanel - Cpanel/Server/Type/Role/MailReceive.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::MailReceive - MailReceive role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::MailReceive;

    my $role = Cpanel::Server::Type::Role::MailReceive->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls mail services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );

our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/mailreceive";

our $SERVICES = [
    'cpanel-dovecot-solr',
    'cpdavd',
    'cpgreylistd',
    'dovecot',
    'imap',
    'mailman',
    'pop',
];

our $RESTART_SERVICES = [qw(cpdavd)];

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("Receive Mail");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("Receive Mail allows users to receive email, as well as create and manage their email accounts.");
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

sub RESTART_SERVICES { return $RESTART_SERVICES; }

1;
