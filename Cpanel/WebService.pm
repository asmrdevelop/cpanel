package Cpanel::WebService;

# cpanel - Cpanel/WebService.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $try_bind_seconds = 240;    # seconds to try binding to a port before giving up, maybe from config?

use Cpanel::Config::IPv6      ();
use Cpanel::IP::Loopback      ();
use Cpanel::IP::Collapse      ();
use Cpanel::Socket::Constants ();

my $EADDRINUSE   = 98;
my $EAFNOSUPPORT = 97;
my $QLEN         = 5;

our $SOL_TCP      = 6;
our $TCP_FASTOPEN = 23;

my $FORCE_KILL_TIMEOUT          = 0;
my $GRACEFUL_KILL_TIMEOUT       = 6;
my $MAX_ATTEMPTS_BEFORE_WAITING = 10;

# $GRACEFUL_KILL_TIMEOUT * $MAX_GRACEFUL_KILLS should always be less than 5 minutes to avoid
# chkservd trying to start cpsrvd again
my $MAX_GRACEFUL_KILLS = 2;

sub setupservice {
    my $port    = shift or die "Missing port!";
    my $timeout = shift || $try_bind_seconds;

    my @fds;

    my $ipv6 = Cpanel::Config::IPv6::should_listen();

    local $SIG{'ALRM'} = sub { die "Port unavailable for $timeout seconds, giving up\n" };
    alarm $timeout;

    my $loop_count = 0;
    my $need_bind  = 1;

  BIND_LOOP:
    while ($need_bind) {
        local $^F = 1000;    #prevent cloexec

        my $fd;

        if ( !socket( $fd, ( $ipv6 ? $Cpanel::Socket::Constants::PF_INET6 : $Cpanel::Socket::Constants::PF_INET ), $Cpanel::Socket::Constants::SOCK_STREAM, $Cpanel::Socket::Constants::IPPROTO_TCP ) ) {    #AF_INET, SOCK_STREAM
            $ipv6 = 0;                                                                                                                                                                                       #fallback to ipv4
            next BIND_LOOP;
        }

        setsockopt( $fd, $Cpanel::Socket::Constants::SOL_SOCKET, $Cpanel::Socket::Constants::SO_REUSEADDR, 1 );                                                                                              #reuse addr

        my $addr_name = $ipv6 ? pack( 'SnNH32N', $Cpanel::Socket::Constants::AF_INET6, $port, 0, "0" x 32, 0 ) : pack( 'Sn4x8', $Cpanel::Socket::Constants::AF_INET, $port, "0" x 4 );

        if ( bind( $fd, $addr_name ) && listen( $fd, 45 ) && $fd ) {
            select( ( select($fd), $| = 1 )[0] );    ## no critic qw(Variables::RequireLocalizedPunctuationVars InputOutput::ProhibitOneArgSelect) --                                                                                                                                                           #aka $fd->autoflush(1);

            setsockopt( $fd, $SOL_TCP, $TCP_FASTOPEN, $QLEN );    # onyl works on cent7

            if ( $ipv6 && exists $INC{'IO/Socket/INET6.pm'} ) {
                bless $fd, 'IO::Socket::INET6';
            }
            elsif ( exists $INC{'IO/Socket/INET.pm'} ) {
                bless $fd, 'IO::Socket::INET';
            }

            push @fds, $fd;

            if ($ipv6) {
                $ipv6 = 0;
                next BIND_LOOP;    #handle net.ipv6.bindv6only=1
            }
            else {
                last BIND_LOOP;
            }
        }

        my $code = int $!;
        if ( $ipv6 && ( $code == $EAFNOSUPPORT || $! =~ /not supported/i ) ) {
            print STDERR "IPv6 not available while attempting to bind to port $port ($!).  Switching to IPv4.\n";
            $ipv6 = 0;
            next BIND_LOOP;
        }
        if ( !$ipv6 && @fds && $code == $EADDRINUSE ) {
            last BIND_LOOP;    #handle net.ipv6.bindv6only=0
        }
        if ( $loop_count++ > $MAX_ATTEMPTS_BEFORE_WAITING ) {
            print STDERR "$0: Waiting to bind to port $port ($!)....\n";
            sleep(1);
        }
        _kill_apps_on_port( $loop_count > $MAX_GRACEFUL_KILLS ? $FORCE_KILL_TIMEOUT : $GRACEFUL_KILL_TIMEOUT, $port );
    }
    alarm 0;

    return \@fds;
}

sub read_socket_headers {
    my $socket = shift;
    my $getreq;
    while ( !$getreq ) {
        $getreq = readline($socket);
        if ($getreq) {
            if ( $getreq =~ /^[\r\n]*$/ ) {
                $getreq = '';
                next;
            }
            last;
        }
        exit;
    }
    {
        local $/ = ( ( $getreq =~ tr/\r// ? "\r\n" : "\n" ) x 2 );
        readline($socket);
    }
    $getreq =~ s/[\r\n]+$//;    #safe chmop GLOBAL
    return $getreq;
}

# We do not need to expand here as we are always fetching these with an unpack
sub remote_host_is_localhost {
    if ( $ENV{'HTTP_PROXIED'} ) { die "remote_host_is_localhost must be called before HTTP_PROXIED is set"; }
    return Cpanel::IP::Loopback::is_loopback( $ENV{'REMOTE_ADDR'} ) ? 1 : 0;
}

sub set_remote_addr_from_socket {
    my $socket   = shift;
    my $peername = getpeername($socket);
    my ( $sock_type, $port ) = unpack( 'Sn', $peername );

    if ( $sock_type == $Cpanel::Socket::Constants::AF_INET6 ) {
        my ( $sock_type, $port, $flow, $ip ) = unpack( 'SnNH32', $peername );
        $ENV{'REMOTE_ADDR'} = Cpanel::IP::Collapse::collapse( join( '.', join( ":", unpack( "H4" x 8, pack( "H32", $ip ) ) ) ) );    ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    }
    else {
        my ( $sock_type, $port, @ip ) = unpack( 'SnC4', $peername );
        $ENV{'REMOTE_ADDR'} = join( '.', @ip );                                                                                      ## no critic qw(Variables::RequireLocalizedPunctuationVars)
    }

    return ( $ENV{'REMOTE_ADDR'}, $port );
}

sub get_ip_versions_to_bind {
    return 'ipv4' if !Cpanel::Config::IPv6::should_listen();

    my $port = 0;
    my @bind_methods;
    my @fds;
    for my $ipv6 ( 1, 0 ) {
        my $fd;

        my $socket_domain = $ipv6 ? $Cpanel::Socket::Constants::PF_INET6 : $Cpanel::Socket::Constants::PF_INET;

        next if !socket( $fd, $socket_domain, $Cpanel::Socket::Constants::SOCK_STREAM, $Cpanel::Socket::Constants::IPPROTO_TCP );    #AF_INET, SOCK_STREAM

        my $addr_name = $ipv6 ? pack( 'SnNH32N', $Cpanel::Socket::Constants::AF_INET6, $port, 0, "0" x 32, 0 ) : pack( 'Sn4x8', $Cpanel::Socket::Constants::AF_INET, $port, 0 );

        # If the system has no ipv6 support fd will be undef
        next if !bind( $fd, $addr_name );

        my $sockname = getsockname($fd);
        my ( $sock_type, $sock_port ) = unpack( 'Sn10', $sockname );
        my $bind_method = ( $sock_type == $Cpanel::Socket::Constants::AF_INET6 ) ? 'ipv6' : 'ipv4';
        push @fds, $fd;                                                                                                              # keep the fds open to make sure we can bind ipv4 or not
        $port ||= $sock_port;

        #handle net.ipv6.bindv6only=1
        push @bind_methods, $bind_method;
    }

    return @bind_methods;
}

sub _kill_apps_on_port {
    my ( $timeout, $port ) = @_;

    # We use system() here rather than C::SR::Object since this module
    # is used in dormant mode, which must be kept as light as possible.
    return system '/usr/local/cpanel/etc/init/kill_apps_on_ports', '--timeout=' . $timeout, $port;
}

1;
