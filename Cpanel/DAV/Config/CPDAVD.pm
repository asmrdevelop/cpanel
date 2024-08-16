
# cpanel - Cpanel/DAV/Config/CPDAVD.pm             Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Config::CPDAVD;

use strict;
use warnings;

use parent "Cpanel::DAV::Config::Base";

use Cpanel::DAV::Principal    ();
use Cpanel::DAV::AddressBooks ();
use Cpanel::DAV::Calendars    ();

=head1 NAME

CPANEL::DAV::Config::CPDAVD

=head1 SYNOPSIS

Module for defining the routes to getting Calendar and Contacts information for the native cpdavd backend.

=head1 DESCRIPTION

Used only within the context of Cpanel::DAV::Config::get_calendar_contacts_config, see example usage there.
Basically this is how to tell the system what URLs, etc you need to return for a calendar in order for
it to properly display in the UI.

=head1 SEE ALSO

Cpanel::DAV::Config::Base

=head1 METHODS

=head2 PRINCIPAL_PATH

Returns a STRING which is the path to the principal data URL (relative to the server's root).

=cut

sub PRINCIPAL_PATH {
    return "principals/$_[0]->{'user'}";
}

=head2 FREEBUSY_PATH

Returns a STRING which is the path to the free/busy data URL (relative to the server's root).

=cut

sub FREEBUSY_PATH {
    return "fb/$_[0]->{user}";
}

=head2 get_principal

Returns an OBJECT of the Cpanel::DAV::Principal type, due to get_contacts and get_calendars relying on said object later.

=cut

sub get_principal {
    my ($self) = @_;
    return Cpanel::DAV::Principal->new( name => $self->{user} );
}

=head2 get_contacts

Returns an ARRAY of contact information HASHREFs.

=cut

sub get_contacts {
    my ( $self, $principal ) = @_;
    return Cpanel::DAV::AddressBooks::get_addressbooks($principal);
}

=head2 get_calendars

Returns an ARRAY of calendar information HASHREFs.

=cut

sub get_calendars {
    my ( $self, $principal ) = @_;
    return Cpanel::DAV::Calendars::get_calendars($principal);
}

1;
