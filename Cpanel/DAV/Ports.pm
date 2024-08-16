
# cpanel - Cpanel/DAV/Ports.pm                     Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::DAV::Ports;

use cPstrict;

use Cpanel::Locale::Lazy 'lh';

use Cpanel::Server::Type::Role::CalendarContact ();    # PPI NO PARSE - used indirectly
use Cpanel::Server::Type::Role::WebDisk         ();    # PPI NO PARSE - used indirectly
use Cpanel::DAV::Provider                       ();

=head1 NAME

Cpanel::DAV::Ports

=head1 DESCRIPTION

This module contains the definition for the ports where cpdavd hosts the various
DAV services.

=cut

# Ports for when the WebDisk role is disabled …
my @WEBDISK_PORTS = (
    {
        port    => 2077,
        service => 'webdav',
        ssl     => 0,
    },
    {
        port    => 2078,
        service => 'webdav',
        ssl     => 1,
    },
);

# These are only used when both conditions are met:
#   - The Calendar and Contacts role is enabled
#   - The active calendar backend is CCS
my @CALDAV_CARDDAV_PORTS = (
    {
        port    => 2079,
        service => 'caldavcarddav',
        ssl     => 0,
    },
    {
        port    => 2080,
        service => 'caldavcarddav',
        ssl     => 1,
    },
);

# This is only used when:
#   - The Calendar and Contacts role is enabled
my @ACTIVESYNC_PORTS = (
    {
        port    => 2091,
        service => 'activesync',
        ssl     => 1,
    },
);

=head1 FUNCTIONS

=head2 get_ports

Gets the ports used in WebDAV, CalDAV, CardDAV and ActiveSync.

Arguments

is_cpdavd - (TRUTHY) whether or not cpdavd is the caller, as if cpdavd is
calling, we don't need to return any cal/carddav ports at this time.

Returns

  - Hash - Ports in name/value pairs.

=cut

sub get_ports {
    my ($is_cpdavd) = @_;
    my $ports = {};
    foreach my $port_info ( _get_ports_list() ) {
        my $port_name;
        my $port_suffix = $port_info->{ssl} ? '_SSL_PORT' : '_NO_SSL_PORT';
        if ( $port_info->{service} eq 'webdav' ) {
            $port_name = 'WEB_DAV' . $port_suffix;
        }
        elsif ( $port_info->{service} eq 'caldavcarddav' ) {

            $port_name = 'CALENDAR_AND_CARD_DAV' . $port_suffix;
        }
        elsif ( $port_info->{service} eq 'activesync' ) {
            $port_name = 'ACTIVE_SYNC' . $port_suffix;
        }
        next if !$port_name;
        $ports->{$port_name} = $port_info->{port};
    }

    return $ports;
}

=head2 accepting_connections

Generates the connection string for the DAV service depending on the arguments passed. Defaults to requiring ssl if missing.

Arguments

n/a

Returns

  - String

=cut

sub accepting_connections {
    my @port_list = map { $_->{port} } _get_ports_list();
    return "cpdavd - accepting connections on: " . join( ', ', @port_list );
}

=head2 is_ssl_port

Checks whether the provided port number is a known SSL port for the DAV services.

Arguments

- $port - numeric - The port number to check

Returns

- Boolean - True if the port is an SSL port; false otherwise

Throws

This function throws an exception if the provided port is unknown. If this ever happens,
it indicates that there is a bug in the calling code (probably listening on an unexpected
port).

=cut

sub is_ssl_port {
    my ($port) = @_;
    die( lh()->maketext( 'The port “[_1]” is not valid.', $port ) ) if !$port;
    my $all_ports = get_ports();
    for my $port_name ( sort keys %$all_ports ) {
        if ( $all_ports->{$port_name} == $port ) {
            return 0 if $port_name =~ /_NO_SSL_PORT$/;
            return 1 if $port_name =~ /_SSL_PORT$/;
        }
    }
    die( lh()->maketext( 'The port “[_1]” is not a known [asis,DAV] service port.', $port ) );
}

=head2 get_port

Look up the port for a service.

Arguments

  - %args - Hash
    - service - String  - The name of the service (may be either 'webdav' or 'caldavcarddav')
    - ssl     - Boolean - Whether to look up the SSL port for the service

Returns

The port number

Throws

This function throws an exception if, for any reason, it can't return a valid port number.

=cut

sub get_port {
    my %args        = @_;
    my $service     = $args{service} || die('You must specify a service.');
    my $ssl         = $args{ssl} // die('You must specify a value for ssl.');
    my ($port_info) = grep { $_->{service} eq $service && $_->{ssl} == $ssl } _get_ports_list()
      or die("Could not find the $service port for ssl=$ssl.");
    return $port_info->{port};
}

=head2 get_ssl_port

Given a non-SSL port, returns the SSL equivalent of that port (for DAV services only).

Arguments

- $non_ssl_port - numeric - The non-SSL port for which to look up the SSL port

Returns

The SSL port corresponding to the provided non-SSL port.

Throws

This function will throw an exception if, for any reason, it's not able to find the
SSL port you asked for.

=cut

sub get_ssl_port {
    my ($non_ssl_port) = @_;
    $non_ssl_port or die( lh()->maketext('You must specify a non-SSL port in order to look up the SSL port.') );

    my ($non_ssl_port_info) = grep { $_->{port} == $non_ssl_port } _get_ports_list()
      or die( lh()->maketext('Port [_1] is not a known DAV port.') );    # If this error ever occurs, it's a bug somewhere in the code.

    my ($ssl_port_info) = grep { $_->{service} eq $non_ssl_port_info->{service} && $_->{ssl} } _get_ports_list()
      or die( lh()->maketext('Could not find the SSL equivalent of port [_1].') );    # If this error ever occurs, it's a bug specifically in this module.

    return $ssl_port_info->{port};
}

=head2 port_is_service_type

Given a port number and service type(s), returns true if the port matches any of the given types.

Named Arguments

- port - numeric - The port number to match against the given type(s).
- type - array ref - One or more types to match against the given port.

Returns

1 if the port matches a given type, 0 otherwise.

Throws

This function will throw an exception if the port argument is undefined, the
type argument is not an array ref, or any of the provided types are unknown.

=cut

sub port_is_service_type (%args) {
    my $port    = delete $args{'port'} // die 'port argument is not defined';
    my $type_ar = delete $args{'type'};
    die 'type argument must be an array ref' unless ref $type_ar eq 'ARRAY';
    my $srv_hr = _get_all_ports_by_service();
    foreach my $type ( @{$type_ar} ) {
        die "unknown type: $type" unless defined $srv_hr->{$type};
        return 1 if defined $srv_hr->{$type}->{$port};
    }
    return 0;
}

#----------------------------------------------------------------------

#overwritten in tests
sub _is_role_enabled {
    return "Cpanel::Server::Type::Role::$_[0]"->is_enabled();
}

sub _get_ports_list {
    my $calendarcontact_enabled = _is_role_enabled('CalendarContact');
    my $webdisk_enabled         = _is_role_enabled('WebDisk');
    my $installed_caldav_server = Cpanel::DAV::Provider::installed();

    return (
        ( $calendarcontact_enabled && defined $installed_caldav_server ? @CALDAV_CARDDAV_PORTS : () ),
        ( $calendarcontact_enabled                                     ? @ACTIVESYNC_PORTS     : () ),
        ( $webdisk_enabled                                             ? @WEBDISK_PORTS        : () ),
    );
}

sub _get_all_ports_list {
    return ( @CALDAV_CARDDAV_PORTS, @ACTIVESYNC_PORTS, @WEBDISK_PORTS );
}

sub _get_all_ports_by_service {
    my %by_service;
    foreach my $ref ( _get_all_ports_list() ) {
        my %attrs   = %{$ref};                    # copy
        my $service = delete $attrs{'service'};
        my $port    = delete $attrs{'port'};
        $by_service{$service}{$port} = \%attrs;
    }
    return \%by_service;
}

1;
