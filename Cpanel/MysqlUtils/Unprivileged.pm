package Cpanel::MysqlUtils::Unprivileged;

# cpanel - Cpanel/MysqlUtils/Unprivileged.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Try::Tiny;

use Cpanel::Socket::Constants        ();
use Cpanel::Socket::Timeout          ();
use Cpanel::Autodie                  ();
use Cpanel::Autodie                  ();
use Cpanel::Socket::UNIX::Micro      ();
use Cpanel::MysqlUtils::MyCnf::Basic ();
use Cpanel::IP::Loopback             ();

my $MYSQL_MAX_PACKET_SIZE = 1_048_576;      # Required value for the handshake but otherwise is not relevant.
my $MYSQL_CHARSET         = 0xff;           # utf8mb4 -- required value for the handshake but otherwise is not relevant.
my $MYSQL_USERNAME        = __PACKAGE__;    # Will appear in MySQL log
my $MYSQL_AUTH_RESPONSE   = q{};

use constant {
    _ECONNREFUSED => 111,

    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_packets.html
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_dt_integers.html#sect_protocol_basic_dt_int_fixed
    # pack can't handle the MySQL int<3> value natively, so the entire 2-part header is treated as one 32-bit little-endian value and shifted/masked separately.
    # NOTE: Because it needs to be packed/unpacked as a single "little-endian" value, the order of the length/sequence values are swapped compared to the MySQL docs!
    MYSQL_PACKET_HEADER_SEQUENCE_SHIFT      => 24,          # Bits to shift to get the sequence_id in the unpacked value
    MYSQL_PACKET_HEADER_PAYLOAD_LENGTH_MASK => 0xffffff,    # Bitmask of the payload_length in the unpacked value
    MYSQL_PACKET_HEADER_TEMPLATE            => q{
        L<  # int<3> payload length (little-endian), exclusive of itself and packet sequence number, then int<1> packet sequence (on the wire, but is swapped when unpacked)
    },

    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_err_packet.html
    # This exists in the payload, not the packet header.
    MYSQL_GENERIC_ERR => 0xff,

    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_connection_phase.html#sect_protocol_connection_phase_initial_handshake
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_connection_phase_packets_protocol_handshake_v10.html
    # Only protocol 10 is supported here, used in MySQL 3.21 through 8.0 (latest available at this time)
    MYSQL_PROTOCOL_VERSION           => 10,
    MYSQL_HANDSHAKE_INITIAL_TEMPLATE => q{
        C   # protocol_version
        Z*  # server_version (string)
            # There is more. Not needed here.
    },

    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_connection_phase_packets_protocol_handshake_response.html#sect_protocol_connection_phase_packets_protocol_handshake_response41
    # Only response version 4.1 is supported here, used in MySQL 4.1 through 8.0 (latest available at this time)
    MYSQL_HANDSHAKE_RESPONSE_TEMPLATE => q{
        L   # capability flags
        L   # max-packet size
        C   # character set
        x23 # reserved
        Z*  # username (string)
        Z*  # auth-response (string)
    },

    # https://dev.mysql.com/doc/dev/mysql-server/latest/group__group__cs__capabilities__flags.html
    MYSQL_CLIENT_PROTOCOL_41 => 0x200,
};

# overridden in tests
sub _TIMEOUT { return 60; }

#It’s actually kind of a bad thing for security that MySQL exposes its
#version to anything that bothers to connect. But, we might as well capitalize
#on it for speed; this lets us get the version number without forking or
#even doing a full connection.
#
#This returns the version as the server gives in the initial MySQL
#handshake. If the server is down, undef is returned. Any other state
#(e.g., timeout, failure to create a socket, MySQL rejecting the connection)
#will prompt an appropriate exception.
#
#NOTE: Consider Cpanel::MysqlUtils::Version, which has logic
#to wrap this with a cache.
#
sub get_version_from_host {
    my ( $host, $port ) = @_;

    my $version;

    if ( my $client = _get_socket( $host, $port ) ) {

        my $payload_length;
        my $sequence_id;
        my $payload_ar;

        my $buffer = q<>;

        my $protocol;

        my $r_timeout = Cpanel::Socket::Timeout::create_read( $client, _TIMEOUT() );
        my $w_timeout = Cpanel::Socket::Timeout::create_write( $client, _TIMEOUT() );
        while ( !$version ) {

            # An empty (successful) read means we’re done.
            last if !Cpanel::Autodie::sysread_sigguard( $client, $buffer, 512, length $buffer );

            ( $payload_length, $sequence_id, $payload_ar ) = _decode_mysql_packet( MYSQL_HANDSHAKE_INITIAL_TEMPLATE(), \$buffer );
            ( $protocol, $version ) = @{$payload_ar};
        }

        if ( $protocol == MYSQL_GENERIC_ERR() ) {
            my ( $errnum, $str ) = unpack 'v a*', $version;
            die "MySQL connection error $errnum: $str";
        }

        if ( $protocol != MYSQL_PROTOCOL_VERSION() ) {
            die "Unknown MySQL protocol: $protocol";
        }

        if ( defined $version && index( $version, 'MariaDB' ) > 0 ) {
            my ( $cap, $v, $name ) = split( '-', $version );
            $version = $v . '-' . $name if $name && $name eq 'MariaDB';
        }

        # A response is not required to obtain the server version, but intends to improve
        # signal-to-noise ratio, so there is no error catch. Without it, the server would log "Got
        # an error reading communication packets". Instead, this response generates "Access denied
        # for user 'Cpanel::MysqlUtils::Unprivileged'@'localhost' (using password: NO)". Since a
        # logged message is unavoidable without authenticating as a real user and quitting cleanly,
        # this at least provides a clue to the cause of the log entry.
        try {
            # Inform the other side not to send any more.
            shutdown $client, $Cpanel::Socket::Constants::SHUT_RD;

            # Drain the socket in case there is anything left in it to avoid ECONNRESET
            1 while sysread( $client, my $buf, 65536 );

            my $response_ref = _encode_mysql_packet(
                ++$sequence_id,
                MYSQL_HANDSHAKE_RESPONSE_TEMPLATE(),
                [
                    MYSQL_CLIENT_PROTOCOL_41(),
                    $MYSQL_MAX_PACKET_SIZE,
                    $MYSQL_CHARSET,
                    $MYSQL_USERNAME,
                    $MYSQL_AUTH_RESPONSE,
                ]
            );

            Cpanel::Autodie::syswrite_sigguard( $client, ${$response_ref} );
        };
        close $client;
    }
    return $version;
}

#stubbed in tests
sub _get_socket {
    my ( $host, $port ) = @_;

    my $client;

    #For local MySQL we can probably connect via local socket,
    #which will be faster than TCP/IP.
    if ( !$host || Cpanel::IP::Loopback::is_loopback($host) ) {
        my $socket_path = _get_socket_path();

        if ( -S $socket_path ) {
            try {
                Cpanel::Autodie::socket(
                    $client,
                    $Cpanel::Socket::Constants::AF_UNIX,
                    $Cpanel::Socket::Constants::SOCK_STREAM,
                    0,
                );

                my $usock = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($socket_path);

                my $timeout = Cpanel::Socket::Timeout::create_write( $client, _TIMEOUT() );

                Cpanel::Autodie::connect( $client, $usock );
            }
            catch {
                warn "Failed to connect to “$socket_path”; will fall back to TCP/IP. ($_)";
                undef $client;
            };
        }
    }

    unless ($client) {
        $port ||= _get_tcp_port();

        require Cpanel::Socket::IP;

        try {
            my %args = (
                PeerPort => $port,
                Timeout  => 5,
            );
            $args{PeerAddr} = $host if $host;
            ($client) = Cpanel::Socket::IP->new(%args);
        }
        catch {

            # Any failure other than ECONNREFUSED means we don’t know
            # whether the server is up.
            if ( $_->get('error') != _ECONNREFUSED ) {
                local $@ = $_;
                die;
            }
        };
    }

    return $client;
}

sub _get_socket_path {
    my $socket_path = Cpanel::MysqlUtils::MyCnf::Basic::getmydbsocket('root');

    $socket_path ||= do {
        require Cpanel::Mysql::Constants;
        Cpanel::Mysql::Constants::DEFAULT()->{'datadir'} . '/' . Cpanel::Mysql::Constants::DEFAULT_UNIX_SOCKET_NAME();
    };

    return $socket_path;
}

sub _get_tcp_port {
    return Cpanel::MysqlUtils::MyCnf::Basic::getmydbport('root') // do {
        require Cpanel::Mysql::Constants;
        Cpanel::Mysql::Constants::DEFAULT()->{'port'};
    };
}

sub _encode_mysql_packet ( $sequence, $template, $payload_ar ) {

    my $packet         = pack( $template, @{$payload_ar} );
    my $payload_length = length $packet;
    $packet = pack( MYSQL_PACKET_HEADER_TEMPLATE(), $payload_length | $sequence << MYSQL_PACKET_HEADER_SEQUENCE_SHIFT() ) . $packet;
    return \$packet;
}

sub _decode_mysql_packet ( $template, $packet_ref ) {

    # Minimum length w/ header
    return unless length ${$packet_ref} >= 4;

    my ( $header, @payload ) = unpack( MYSQL_PACKET_HEADER_TEMPLATE() . $template, ${$packet_ref} );

    # The first unpacked 8 bits are the sequence.
    my $sequence_id = $header >> MYSQL_PACKET_HEADER_SEQUENCE_SHIFT();

    # The last unpacked 24 bits are the length.
    my $payload_length = $header & MYSQL_PACKET_HEADER_PAYLOAD_LENGTH_MASK();

    # Return in documented packet order.
    return ( $payload_length, $sequence_id, \@payload );
}

1;
