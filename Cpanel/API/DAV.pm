package Cpanel::API::DAV;

# cpanel - Cpanel/API/DAV.pm                       Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

require 5.014;

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the API calls and support code related to the calendar and
# contacts client configuration applications available in cPanel and Webmail.
#-------------------------------------------------------------------------------------------------

use Cpanel::DAV::Config       ();
use Cpanel::Services::Enabled ();

use Try::Tiny;

=head1 NAME

Cpanel::API::DAV

=head1 DESCRIPTION

UAPI functions related to the management of Calendars and Contacts by cPanel and Webmail users.

=head2 get_calendar_contacts_config

=head3 Purpose

Fetches a configuration object containing the connection information for setting up CalDAV and
CardDAV clients.

=head3 Arguments

  user - optional user. If missing, will default to the current user. If provided and in
  the cPanel context, will returned a filled in data structure for the requested user.
  Currently, no attempt is made to verify the user is a legal user of that account. If
  provided in the Webmail context, the user parameter is ignored and the configuration data
  is filled in for the current user only.

=head3 Returns

=over

=item Hash with the following structure.

=over

=item 'user': string - user name the config is for.

=item 'ssl':  hash - configuration for ssl connections.

=over

=item 'port': number - port used for ssl connections.

=item 'server': string - short server connection string. Valid if the client support auto-discovery.

=item 'full_server': string - full url path to the users principal. Useful for clients that do not support auto-discovery.

=item 'is_self_signed': boolean - truthy if the domains certificate is self-signed, falsey otherwise.

=item 'contacts': array - list of address books for this account where each item is the array has the structure

=over

=item 'name': string - Name of the address book.

=item 'description': string - User provided description of the address book

=item 'path': string - Relative path to this resource.

=item 'url': string - Full ssl url to this resource.

=back

=item 'calendars': array - list of calendars for this account where each item is the array has the structure

=over

=item 'name': string - Name of the calendar.

=item 'description': string - User provided description of the calendar

=item 'path': string - Relative path to this resource.

=item 'url': string - Full ssl url to this resource.

=back

=back

=item 'no_ssl': hash - configuration for non-ssl connections.

=over

=item 'port': number - port used for non-ssl connections.

=item 'server': string - short server connection string. Valid if the client support auto-discovery.

=item 'full_server': string - full url path to the users principal. Useful for clients that do not support auto-discovery.

=item 'contacts': array - list of address books for this account where each item is the array has the structure

=over

=item 'name': string - Name of the address book.

=item 'description': string - User provided description of the address book

=item 'path': string - Relative path to this resource.

=item 'url': string - Full non-ssl url to this resource.

=back

=item 'calendars': array - list of calendars for this account where each item is the array has the structure

=over

=item 'name': string - Name of the calendar.

=item 'description': string - User provided description of the calendar

=item 'path': string - Relative path to this resource.

=item 'url': string - Full non-ssl url to this resource.

=back

=back

=back

=back

=cut

sub get_calendar_contacts_config {
    my ( $args, $result ) = @_;
    my ($user) = $args->get(qw( user ));

    my $config = Cpanel::DAV::Config::get_calendar_contacts_config($user);

    $result->data($config);
    return 1;
}

=head2 is_dav_service_enabled

=head3 Purpose

Checks if cpdavd is enabled on the system.

=head3 Arguments

None

=head3 Returns

=over

=item Hash with the following structure.

=over

=item 'enabled': boolean - truthy if enabled, falsy otherwise.

=back

=back

=cut

sub is_dav_service_enabled {
    my ( $args, $result ) = @_;
    $result->data( { enabled => Cpanel::Services::Enabled::is_enabled('cpdavd') ? 1 : 0 } );
    return 1;
}

=head2 has_shared_global_addressbook

=head3 Purpose

Determines and reports if the global addressbook for a cPanel user is shared or not

=head3 Arguments

=over

=item Hash with the following structure:

=over

=item 'name': string - optional, the cpanel user name or an email address of a webmail user. If not provided, will default to the current user.

=back

=back

=head3 Returns

=over

=item Hash with the following structure:

=over

=item 'shared': boolean - indicates the current shared status of the user's shared address book

=back

=back

=cut

# Until we get a calendar server that supports this again, return 0
sub has_shared_global_addressbook {
    return 0;
}

=head2 enable_shared_global_addressbook

=head3 Purpose

Turns on sharing for the addressbook with all the webmail accounts for the current account.

=head3 Arguments

=over

=item Hash with the following structure:

=over

=item 'name': string - optional, the cpanel user name or an email address of a webmail user. If not provided, will default to the current user.

=back

=back

=head3 Returns

=over

=item Hash with the following structure:

=over

=item 'shared': boolean - indicates the current shared status of the user's shared address book

=back

=back

=cut

# No-op till we get a calendar server that supports this again
sub enable_shared_global_addressbook {
    my ( $args, $result ) = @_;
    my $name = $args->get(qw( name ));

    $result->data( { shared => 0 } );
    return 1;
}

=head2 disable_shared_global_addressbook

=head3 Purpose

Turns off sharing for the addressbook with all the webmail accounts for the current account.

=head3 Arguments

=over

=item Hash with the following structure:

=over

=item 'name': string - optional, the cpanel user name or an email address of a webmail user. If not provided, will default to the current user.

=back

=back

=head3 Returns

=over

=item Hash with the following structure:

=over

=item 'shared': boolean - indicates the current shared status of the user's shared address book

=back

=back

=cut

# Pretend for now
sub disable_shared_global_addressbook {
    my ( $args, $result ) = @_;
    my $name = $args->get(qw( name ));

    $result->data( { shared => 0 } );

    return 1;
}

my $allow_demo = {
    allow_demo => 1,
};

our %API = (
    _worker_node_type => 'Mail',

    get_calendar_contacts_config      => $allow_demo,
    is_dav_service_enabled            => $allow_demo,
    has_shared_global_addressbook     => $allow_demo,
    enable_shared_global_addressbook  => $allow_demo,
    disable_shared_global_addressbook => $allow_demo,
);

1;
