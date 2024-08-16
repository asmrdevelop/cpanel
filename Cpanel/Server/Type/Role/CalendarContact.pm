package Cpanel::Server::Type::Role::CalendarContact;

# cpanel - Cpanel/Server/Type/Role/CalendarContact.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Server::Type::Role::CalendarContact - CalendarContact role for server profiles

=head1 SYNOPSIS

    use Cpanel::Server::Type::Role::CalendarContact;

    my $role = Cpanel::Server::Type::Role::CalendarContact->new();
    my $is_enabled = $role->is_enabled();

=head1 DESCRIPTION

Subclass of C<Cpanel::Server::Type::Role> that controls CalDAV and CardDAV services and features

=head1 SUBROUTINES

=cut

use strict;
use warnings;

use parent qw(
  Cpanel::Server::Type::Role::TouchFileRole
);

my ( $NAME, $DESCRIPTION );

our $TOUCHFILE = $Cpanel::Server::Type::Role::TouchFileRole::ROLES_TOUCHFILE_BASE_PATH . "/calendarcontact";

our $SERVICES = [
    'cpdavd',
];

our $RESTART_SERVICES = [qw(cpdavd)];

sub _NAME {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $NAME ||= Cpanel::LocaleString->new("Calendars and Contacts");
    return $NAME;
}

sub _DESCRIPTION {
    require 'Cpanel/LocaleString.pm';    ## no critic qw(Bareword) - hide from perlpkg
    $DESCRIPTION ||= Cpanel::LocaleString->new("Calendars and Contacts provides CalDAV and CardDAV services.");
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

use constant _SERVICE_SUBDOMAINS => [qw(cpcalendars cpcontacts)];

1;
