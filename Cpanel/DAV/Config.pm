package Cpanel::DAV::Config;

# cpanel - Cpanel/DAV/Config.pm                    Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                      ();
use Cpanel::ActiveSync          ();
use Cpanel::DAV::Config::CPDAVD ();    # PPI NO PARSE - to satisfy t/large/detect-unused-packages.t and make the module usage more greppable
use Cpanel::LoadModule          ();
use Cpanel::LoadModule::Custom  ();

use Try::Tiny;

=head1 NAME

Cpanel::DAV::Config

=head1 DESCRIPTION

Fetch the various configuration settings used by external clients of Calendars
and Contacts by cPanel and Webmail users.

=head1 FUNCTIONS

=head2 get_calendar_contacts_config

=head3 Purpose

Fetches a configuration hash containing the connection information for setting
up CalDAV and CardDAV clients.

=head3 Arguments

  user - optional user. If missing, will default to the current user. If
  provided and in the cPanel context, will return a filled in data structure
  for the requested user. Currently, no attempt is made to verify the user is a
  legal user of that account. If provided in the Webmail context, the user
  parameter is ignored and the configuration data is filled in for the current
  user only.

=head3 Returns

=over

=item Hash with the following structure.

=over

=item 'user': string - user name the config is for.

=item 'ssl':  hash - configuration for ssl connections.

=over

=item 'port': number - port used for ssl connections.

=item 'server': string -
short server connection string. Valid if the client support auto-discovery.

=item 'full_server': string -
full url path to the users principal. Useful for clients that do not support
auto-discovery.

=item 'is_self_signed': boolean -
truthy if the domains certificate is self-signed, falsey otherwise.

=item 'contacts': array -
list of address books for this account where each item is the array has the
structure

=over

=item 'name': string - Name of the address book.

=item 'description': string - User provided description of the address book

=item 'path': string - Relative path to this resource.

=item 'url': string - Full ssl url to this resource.

=back

=item 'calendars': array -
list of calendars for this account where each item is the array has the
structure

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

=item 'server': string -
short server connection string. Valid if the client support auto-discovery.

=item 'full_server': string -

full url path to the users principal. Useful for clients that do not support
auto-discovery.

=item 'contacts': array -
list of address books for this account where each item is the array has the
structure

=over

=item 'name': string - Name of the address book.

=item 'description': string - User provided description of the address book

=item 'path': string - Relative path to this resource.

=item 'url': string - Full non-ssl url to this resource.

=back

=item 'calendars': array -
list of calendars for this account where each item is the array has the
structure

=over

=item 'name': string - Name of the calendar.

=item 'description': string - User provided description of the calendar

=item 'path': string - Relative path to this resource.

=item 'url': string - Full non-ssl url to this resource.

=back

=back


=item 'activesync': hash - configuration for ActiveSync connections.

=over

=item 'enabled': boolean - 1 if enabled, 0 if not enabled.

=item 'port': number - port used for secure ActiveSync connections.

=item 'server': string - hostname.

=item 'user': string - username.

=back

=back

=back

=cut

sub get_calendar_contacts_config {
    my ( $user, $driver ) = @_;

    if ( ( $Cpanel::appname || '' ) eq 'webmail' || !$user ) {
        $user = $Cpanel::authuser or die "No user given or detectable!";
    }

    # This can return undef if CCS is not installed and another
    # DAV driver is not configured
    my $conf_obj = get_conf_object( $user, $driver );

    my ( $best_non_ssl_domain, $best_ssl_domain, $is_self_signed );

    # try/catch here in case get_conf_object() returns undef
    try {
        ( $best_non_ssl_domain, $best_ssl_domain, $is_self_signed ) = $conf_obj->get_best_domains();
    }
    catch {
        die lh()->maketext( 'Failed to fetch the address books for [_1]: DAV driver is not currently configured.', $user );
    };

    my $principal     = $conf_obj->get_principal();
    my $contacts_list = [];
    try {
        $contacts_list = $conf_obj->get_contacts($principal);
    }
    catch {
        die lh()->maketext( 'Failed to fetch the address books for [_1]: [_2]', $user, $_ );
    };

    # XXX a bit wasteful to get em this way with HBHB, could do this in one call
    my $calendars_list = [];
    try {
        $calendars_list = $conf_obj->get_calendars($principal);
    }
    catch {
        die lh()->maketext( 'Failed to fetch the calendars for [_1]: [_2]', $user, $_ );
    };

    my $activesync = { enabled => 0 };
    if ( Cpanel::ActiveSync::is_activesync_available_for_user( $Cpanel::user || $user ) ) {
        $activesync = {
            enabled => 1,
            user    => $user,
            server  => $best_ssl_domain,
            port    => Cpanel::ActiveSync::get_ports()->{'ssl'},
        };
    }

    my $config = $conf_obj->get(
        'best_ssl_domain'     => $best_ssl_domain,
        'is_self_signed'      => $is_self_signed,
        'best_non_ssl_domain' => $best_non_ssl_domain,
        'calendar_list'       => $calendars_list,
        'contacts_list'       => $contacts_list,
    );
    $config->{activesync} = $activesync;

    return $config;
}

=head2 get_conf_object

=head3 Purpose

Fetches the (previously) internal object corresponding to the appropriate
calendar server type, whether that be Apple's CCS or another (if installed).

=head3 Arguments

user (STRING) - If missing, will likely lead to undefined behavior, as the
entire point of getting configuration so far for these servers is in a user
context, whether that means a cPanel or Webmail user. Currently all callers
that use this subroutine already do their own checks regarding whether or not
the user is valid, so you probably should do so as well if you are considering
using this elsewhere.

driver (STRING) - Optionally allows you to override what driver type you want
to load the config object for. Only potential use I can see here is for
scenarios where you are running two calendarservers in parallel (like currently
is the case with our CCS implementation).

=head3 Returns

An object that ISA Cpanel::DAV::Config::$TYPE where $TYPE corresponds to the
active calendarserver indicated in /var/cpanel/calendarserver OR by the second
argument to this subroutine. A DAV provider must be installed, such as CCS, or this
will return undef.

=cut

sub get_conf_object {
    my ( $user, $driver ) = @_;

    # Check for which calendaring solution is installed
    require Cpanel::DAV::Provider;
    my $dav_provider = $driver || Cpanel::DAV::Provider::installed();

    if ( !length($dav_provider) ) {
        return;
    }
    my $dav_namespace = "Cpanel::DAV::Config::$dav_provider";
    Cpanel::LoadModule::Custom::load_perl_module($dav_namespace);
    return $dav_namespace->new($user);
}

my $locale;

sub lh {
    if ( !$locale ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Locale');

        # If cpdavd ever gets compiled, this will need to be quoted as
        # 'Cpanel::Locale'->get_handle()
        $locale = Cpanel::Locale->get_handle();
    }
    return $locale;
}

1;
