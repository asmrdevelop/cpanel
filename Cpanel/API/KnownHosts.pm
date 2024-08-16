package Cpanel::API::KnownHosts;

# cpanel - Cpanel/API/KnownHosts.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Validate::Domain::Tiny ();
use Cpanel::Exception              ();
use Cpanel::Ips::V6                ();
use Cpanel::SSH::KnownHosts        ();
use Cpanel::Validate::Hostname     ();
use Cpanel::Validate::IP::v4       ();

=encoding utf-8

=head1 NAME

Cpanel::API::KnownHosts - UAPI functions to manage entries in ~/.ssh/known_hosts.

=head1 SUBROUTINES

=over 4

=item create()

Creates a new host key entry. This function takes the host name and an optional port
value, returns the following:

=over 4

=item host

An array of hash references, each representing a key associated with the host.

=back

=cut

sub create {
    my ( $args, $result ) = @_;

    my $host_name = $args->get_length_required('host_name');
    my $port      = $args->get('port');

    _validate_arguments( $host_name, $port );

    $result->data( { 'host' => Cpanel::SSH::KnownHosts::add_to_known_hosts( $host_name, $port ) } );

    return 1;
}

=item verify()

Check if a host exists and if the keys have been updated. This function takes
the host name and an optional port value, returns the following:

=over 4

=item status

If the host keys are present and up to date.

=item failure_type

Host keys are not present, or out of date.

=item errors

An array of localized error messages.

=item host

An array of hash references, each representing a host key associated
with the host.

=back

=cut

sub verify {
    my ( $args, $result ) = @_;

    my $host_name = $args->get_length_required('host_name');
    my $port      = $args->get('port');

    _validate_arguments( $host_name, $port );

    my ( $status, $error ) = Cpanel::SSH::KnownHosts::check_known_hosts( $host_name, $port );

    my $data = { 'status' => $status };
    if ($error) {
        $data->{'failure_type'} = $error->{'type'},
          $data->{'errors'} = [ $error->{'error'} ],
          $data->{'host'} = $error->{'host_keys'};
    }

    $result->data($data);

    return 1;
}

=item update()

Update the key for a host. This function takes the host name and an
optional port value,  returns the following:

=over 4

=item host

An array of hash references, each representing a key associated with the host.

=back

=cut

sub update {
    my ( $args, $result ) = @_;

    my $host_name = $args->get_length_required('host_name');
    my $port      = $args->get('port');

    _validate_arguments( $host_name, $port );

    $result->data( { 'host' => Cpanel::SSH::KnownHosts::add_to_known_hosts( $host_name, $port ) } );

    return 1;
}

=item delete()

Delete entry for a host. This function takes the host name and an
optional port value, returne none.

=cut

sub delete {
    my ( $args, $result ) = @_;

    my $host_name = $args->get_length_required('host_name');
    my $port      = $args->get('port');

    _validate_arguments( $host_name, $port );

    Cpanel::SSH::KnownHosts::remove_known_host( $host_name, $port );

    return 1;
}

=item _validate_arguments( host_name, port )

Verify that host name and port are valid. Throws exceptions if they
are not.

=cut

sub _validate_arguments {
    my ( $host, $port ) = @_;

    unless ( Cpanel::Ips::V6::validate_ipv6($host)
        || Cpanel::Validate::IP::v4::is_valid_ipv4($host)
        || Cpanel::Validate::Hostname::is_valid($host)
        || Cpanel::Validate::Domain::Tiny::validdomainname($host) ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The hostname must be a valid domain name, fully-qualified domain name, or IPv4 or IPv6 address.', [] );
    }

    if ( defined $port ) {
        unless ( $port =~ /^\d+$/ && $port >= 1 && $port <= 65535 ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The port number must be an integer between 1 and 65535.', [] );
        }
    }

    return;
}

=back

=cut

1;
