package Cpanel::SSH::Remote;

# cpanel - Cpanel/SSH/Remote.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Alarm      ();
use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Cpanel::Logger     ();
use Cpanel::SSH::Port  ();

my $logger = Cpanel::Logger->new();

my $remote_timeout = 15;    #seconds

sub check_remote_ssh_connection {
    my ( $server, $port ) = @_;

    if ( !length $server ) {
        die Cpanel::Exception::create( 'MissingParameter', 'You must provide a hostname.' );
    }

    if ( $server =~ tr<:><> ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The hostname may not contain the following [numerate,_1,character,characters]: [join, ,_2]', [ 1, [':'] ] );
    }

    if ( !length $port ) {
        $port = $Cpanel::SSH::Port::DEFAULT_SSH_PORT;
    }
    elsif ( !$port || $port !~ m{\A[0-9]+\z} || !( 0 + $port ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid [asis,TCP/IP] port number.', [$port] );
    }

    Cpanel::LoadModule::load_perl_module('IO::Socket::INET');

    my $timeout_exception = Cpanel::Exception::create( 'Timeout', 'The system stopped waiting to connect to “[_1]” on port “[_2]” after [quant,_3,second,seconds].', [ $server, $port, $remote_timeout ] );

    my $alarm = Cpanel::Alarm->new( $remote_timeout, sub { die $timeout_exception; } );

    local $!;
    my $sock = IO::Socket::INET->new(
        'Proto'    => 'tcp',
        'PeerAddr' => $server,
        'PeerPort' => $port,
        'Blocking' => 1,
        'Timeout'  => $remote_timeout,
    );
    if ( !$sock ) {

        #IO::Socket::INET is inconsistent about where it reports errors.
        #cf. https://rt.perl.org/Ticket/Display.html?id=120764
        my $err = $!;
        if ( !length $err ) {
            $err = $@;
            if ( length $err ) {
                $err =~ s{\AIO::Socket::INET:\s+}{};
            }
        }

        if ( !defined $port ) {
            $port = q{};
        }

        die Cpanel::Exception::create( 'ConnectionFailed', 'The system failed to connect to “[_1]” on port “[_2]” because of an error: [_3]', [ $server, $port, $err ] );
    }

    #Redefine this since we've connected.
    $timeout_exception = Cpanel::Exception::create( 'Timeout', 'The system connected to “[_1]” on port “[_2]” but “[_1]” sent no response for [quant,_3,second,seconds], so the system has aborted the connection.', [ $server, $port, $remote_timeout ] );

    #cf. RFC 4253, section 4.2
    my ( $protoversion, $softwareversion, $comment, $ssh_id );
    for ( 0 .. 100 ) {    #100 lines should be safe to try reading ...
        my $new_line = readline $sock;
        die Cpanel::Exception::create_raw( 'SocketReadError', $! ) if $!;
        last                                                       if !defined $new_line;

        $ssh_id .= $new_line;

        if ( $ssh_id =~ m{^SSH-([^\s-]+)-([^\s-]+)(?: (.*\S))?\s*\z}ms ) {
            ( $protoversion, $softwareversion, $comment ) = ( $1, $2, $3 );
            last if defined $protoversion;
        }
    }

    $alarm = undef;

    close $sock or do {
        $logger->warn("Failed to close socket to $server/$port: $!");
    };

    $ssh_id =~ s{\s+\z}{};

    return {
        protocol_versions => $protoversion && [ $protoversion eq '1.99' ? ( 2, 1 ) : $protoversion ],
        server_software   => $softwareversion,
        comment           => $comment,
        received          => $ssh_id,
    };
}

1;
