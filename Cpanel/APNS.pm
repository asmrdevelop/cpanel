package Cpanel::APNS;

# cpanel - Cpanel/APNS.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::APNS - A lightweight Apple Push Notification Service client.

=head1 SYNOPSIS

    use Cpanel::APNS;

    my $apns = Cpanel::APNS->new({
        'cert' => '/var/cpanel/ssl/mail_apns/cert.pem'
        'key'  => '/var/cpanel/ssl/mail_apns/key.pem'
    });

    $apns->write_payload('APPLE_HEX_TOKEN...', {
        'aps' => {
           'account-id' => 'ABC-DEF-1',
           'm' => 'INBOX'
        }
    });

    $apns->write_payload('APPLE_HEX_TOKEN...', {
        'aps' => {
           'account-id' => 'ABC-DEF-1',
           'm' => 'INBOX.Sent'
        }
    });

=head1 NOTES

This module is designed to be as lightweight as possible
as it remains loaded in memory inside of tailwatchd when
active.

=head1 DESCRIPTION

This module sends push notifications to Apple.  It is intended
to support short notifications only.

=cut

use Net::SSLeay            ();
use Cpanel::Alarm          ();
use Cpanel::Autodie        qw( socket connect shutdown_if_connected );
use Cpanel::Exception      ();
use Cpanel::JSON           ();
use Cpanel::NetSSLeay::CTX ();
use Cpanel::NetSSLeay::SSL ();

our $CONNECT_TIMEOUT = 10;
our $WRITE_TIMEOUT   = 3;

#----------------------------------------------------------------------
# See https://developer.apple.com/library/content/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/LegacyNotificationFormat.html
# for payload format
#
# We use the legacy notification format because it is smaller and more purpose built
# for what we are doing (and it’s what Xserver uses)

#A null byte, then 32 as unsigned short big-endian:
use constant _APNS_PAYLOAD_HEADER => qq<\x00\x00\x20>;

use constant _APNS_PAYLOAD_TEMPLATE => q<
    a*  #header
    H*  #device token
    n   #json length
    a*  #json
>;

use constant MAXPAYLOAD_SIZE => 256;

#----------------------------------------------------------------------

=head2 new

Create a new Cpanel::APNS object

=head3 Input

=over 3

=item C<HASHREF>

=over 3

=item cert (required): The path to a certificate in PEM format

=item key  (required): The path to the key for the certificate in PEM format

=item host (optional): The host to send the notification to (defaults to gateway.push.apple.com)

=item port (optional): The port to send the notification to (defaults to 2195)

=back

=back

head3 Output

=over 3

=item A Cpanel::APNS object

=back

=cut

sub new {
    my ( $class, $opts_ref ) = @_;

    if ( !$opts_ref->{'cert'} ) { die "cert is required"; }
    if ( !$opts_ref->{'key'} )  { die "key is required"; }

    _ensure_cert_and_key_readable($opts_ref);

    #Copy so that we don’t alter the passed-in $opts_ref
    my %self = (%$opts_ref);

    $self{'host'} ||= 'gateway.push.apple.com';    # gateway.sandbox.push.apple.com
    $self{'port'} ||= 2195;

    return bless \%self, $class;
}

sub _ensure_cert_and_key_readable {
    my ($opts_ref) = @_;
    for my $key (qw( cert key )) {
        my $head = "“$key” ($opts_ref->{$key})";
        if ( !-r $opts_ref->{$key} ) {
            if ($!) {
                die "$head is unreadable: $!";
            }

            die( sprintf "$head is unreadable! (mode = 0%o)", ( stat _ )[2] );
        }
        if ( !-s _ ) {
            die "$head is empty!";
        }
    }
    return 1;
}

=head2 write_payload

Write a notification payload to the APNS server for a
device token

=head3 Input

=over 3

=item C<SCALAR>

The apple device token in hex format. Example:

    1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef

=item C<HASHREF>

A reference in Apple's push notification format. Example:

    { 'aps' => {'account-id' => 'ABC-....'} }

=back

=head3 Output

=over 3

=item Returns 1 on success

=back

=cut

sub write_payload {
    my ( $self, $devicetoken, $ref ) = @_;

    my $json = Cpanel::JSON::canonical_dump($ref);
    if ( bytes::length($json) > MAXPAYLOAD_SIZE ) {
        die sprintf( "Payload (%s) may not exceed %d bytes", $json, MAXPAYLOAD_SIZE );
    }

    if ( $devicetoken !~ m<\A[0-9a-fA-F]{64}\z> ) {
        die "Device token must be 32 bytes, hex-encoded, not “$devicetoken”";
    }

    my $payload = pack(
        _APNS_PAYLOAD_TEMPLATE,
        _APNS_PAYLOAD_HEADER,
        $devicetoken,
        length($json),
        $json,
    );

    $self->_get_connection() if !$self->{'socket'};

    local $@;
    foreach ( 1 .. 3 ) {

        # For speed we use eval since its possible to send 100s of these
        # in a single second.
        eval {
            local $SIG{'PIPE'} = sub { die "The remote host “$self->{'host'}:$self->{'port'}” unexpectedly closed the connection"; };

            my $alarm = Cpanel::Alarm->new(
                $WRITE_TIMEOUT,
                sub {
                    die Cpanel::Exception::create_raw( 'Timeout', "Timeout while writing to: $self->{'host'}:$self->{'port'}" );
                },
            );

            $self->{'ssl_obj'}->write_all($payload);
        };
        last if !$@;
        $self->_get_connection();
    }
    die if $@;

    return 1;
}

sub _get_connection {
    my ($self) = @_;

    $self->_close_connection() if $self->{'socket'};

    if ( !$self->{'ssl_init'} ) {
        Net::SSLeay::initialize();
        $self->{'ssl_init'} = 1;
    }

    my $proto = getprotobyname('tcp');
    Cpanel::Autodie::socket( $self->{'socket'}, Socket::PF_INET(), Socket::SOCK_STREAM(), $proto );

    my ( $name, $alias, $addrtype, $length, @addrs ) = gethostbyname( $self->{'host'} );

    if ( !@addrs ) {
        die Cpanel::Exception->create( 'The host name “[_1]” does not resolve to any [asis,IPv4] addresses.', [ $self->{'host'} ] );
    }

    my @failures;

    foreach my $addr (@addrs) {
        my $remote_addr = pack( 'Sna4x8', Socket::PF_INET(), $self->{'port'}, $addr );

        local $@;
        eval {
            my $alarm = Cpanel::Alarm->new( $CONNECT_TIMEOUT, sub { die "Timeout while connecting to: $self->{'host'}:$self->{'port'}"; } );
            Cpanel::Autodie::connect( $self->{'socket'}, $remote_addr );
        };
        last if !$@;

        push @failures, [ $addr => $@ ];
    }
    if ( @failures == @addrs ) {
        die( "Could not connect to $self->{'host'}:$self->{'port'}:\n" . join( "\n", map { "$_->[0]: " . Cpanel::Exception::get_string( $_->[1] ) } @failures ) );
    }

    $self->{'ctx_obj'} = Cpanel::NetSSLeay::CTX->new();
    $self->{'ctx_obj'}->set_options('ALL');
    $self->{'ctx_obj'}->use_PrivateKey_file( $self->{'key'}, 'PEM' );
    $self->{'ctx_obj'}->use_certificate_chain_file( $self->{'cert'}, 'PEM' );

    $self->{'ssl_obj'} = Cpanel::NetSSLeay::SSL->new( $self->{'ctx_obj'} );
    $self->{'ssl_obj'}->set_fd( fileno( $self->{'socket'} ) );
    $self->{'ssl_obj'}->connect();

    return 1;
}

sub _close_connection {
    my ($self) = @_;

    local $@;

    # only shutdown writing since close may cause Net::SSLeay to read()
    # Since we keep the connection open and keep writing notifications
    # during the life of the object, we expect the shutdown will sometimes
    # fail because Apple has already disconnected us.  This is normal
    # so we do not fail if we’re not connected.
    Cpanel::Autodie::shutdown_if_connected( $self->{'socket'}, 1 );

    delete $self->{'ssl_obj'};
    delete $self->{'ctx_obj'};

    close( $self->{'socket'} ) or do {
        warn "close() on socket failed: $!";
    };

    delete $self->{'socket'};

    return 1;
}

sub DESTROY {
    my ($self) = @_;

    $self->_close_connection() if $self->{'socket'};

    return 1;
}

=head1 LIMITATIONS

This module only supports notifications of 256 octets or smaller.

This is not a disconnect method, if you wish to disconnect from the APNS server
you should destroy the object.

=cut

1;
