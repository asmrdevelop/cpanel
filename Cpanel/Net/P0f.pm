package Cpanel::Net::P0f;

# cpanel - Cpanel/Net/P0f.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This class should encapsulate all interaction with the p0f daemon.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent 'Cpanel::Net::Base';

use Cpanel::Net::P0f::Config ();

use Cpanel::IP::Convert ();
use Cpanel::Pack        ();

our $P0F_QUERY_MAGIC   = 0x50304601;
our $MAX_RESPONSE_SIZE = 8192;
our $TIMEOUT           = 10;

use constant _PACK_TEMPLATE => [
    magic       => 'I',
    status      => 'I',
    first_seen  => 'I',
    last_seen   => 'I',
    total_conn  => 'I',
    uptime_min  => 'I',
    up_mod_days => 'I',
    last_nat    => 'I',
    last_chg    => 'I',
    distance    => 's',
    bad_sw      => 'C',
    os_match_q  => 'C',
    os_name     => 'A32',
    os_flavor   => 'A32',
    http_name   => 'A32',
    http_flavor => 'A32',
    link_type   => 'A32',
    language    => 'A32',
];

###########################################################################
#
# Method:
#    new
#
# Description:
#    Creates a Cpanel::Net::P0f object
#
# Arguments:
#   'socket_path' (option) - The path to the p0f socket
#
# Returns:
#   Cpanel::Net::P0f object
#

sub new {
    my ( $class, %OPTS ) = @_;

    $OPTS{'socket_path'} ||= $Cpanel::Net::P0f::Config::SOCKET_PATH;

    return $class->SUPER::new(%OPTS);
}

###########################################################################
#
# Method:
#    lookup_address
#
# Description:
#    Lookup an IPv4 or IPv6 address in the p0f database.
#
# Arguments:
#   $address - An IPv4 or IPv6 address
#
# Returns:
#   Cpanel::Net::P0f::Response object -
#     If the lookup was successful and a valid
#     response was received from the p0f server.
#   undef -
#     Returned when any failure is encountered.
#
sub lookup_address {
    my ( $self, $address ) = @_;

    $self->connect_to_unix_socket();
    $self->write_message( $self->generate_p0f_request_from_ip_address($address) );
    my $response = $self->read_response($MAX_RESPONSE_SIZE);
    $self->close_socket();
    return $self->_unpack_p0f_response($response);
}

###########################################################################
#
# Method:
#    generate_p0f_request_from_ip_address
#
# Description:
#    This function generates an p0f request that can be sent
#    to the p0f daemon for a given IPv4 or IPv6 address.
#
# Arguments:
#   $address - An IPv4 or IPv6 address
#
# Returns:
#   A binary p0f request that can be sent to a p0f server.
#
sub generate_p0f_request_from_ip_address {
    my ( $self, $address ) = @_;
    my $ip = Cpanel::IP::Convert::normalize_human_readable_ip($address);
    my ( $binary_ip_address, $ip_version );

    if ( $ip =~ m{:} ) {
        $ip_version = 6;

        #This is always 16 octets.
        $binary_ip_address = Cpanel::IP::Convert::ip2bin16($address);
    }
    else {
        $ip_version = 4;

        #"x12" makes it 16 octets.
        $binary_ip_address = pack( 'C4 x12', split( /\./, $ip ) );
    }
    return pack( 'I C a*', $P0F_QUERY_MAGIC, $ip_version, $binary_ip_address );
}

###########################################################################
#
# Method:
#    _unpack_p0f_response
#
# Description:
#    Unpacks a raw p0f message into a hashref.
#
# Arguments:
#   $buffer - The raw p0f message read from the socket
#
# Returns:
#   A hashref of the unpacked data with the key names
#   that p0f defines.
#

sub _unpack_p0f_response {
    my ( $self, $buffer ) = @_;

    $self->{'_pack_obj'} ||= Cpanel::Pack->new( _PACK_TEMPLATE() );

    my $resp_hr = $self->{'_pack_obj'}->unpack_to_hashref($buffer);

    my $class = ref($self) . '::Response';

    return $class->new($resp_hr);
}

package Cpanel::Net::P0f::Response;

use strict;

my $HTTP_CLIENT_FORGED  = 2;
my $HTTP_CLIENT_PROXIED = 1;

sub new {
    my ( $class, $params_hr ) = @_;

    return bless { _params => $params_hr }, $class;
}

sub get {
    my ( $self, $attr ) = @_;

    return $self->{'_params'}{$attr};
}

sub http_client_is_forged {
    my ($self) = @_;

    return $self->get('bad_sw') & $HTTP_CLIENT_FORGED ? 1 : 0;
}

sub http_client_is_proxied {
    my ($self) = @_;

    return $self->get('bad_sw') & $HTTP_CLIENT_PROXIED ? 1 : 0;
}

1;
