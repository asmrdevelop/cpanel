package Cpanel::HttpTimer;

# cpanel - Cpanel/HttpTimer.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION      = 1.3;
our $MAX_SIZE     = 1024**2;
our $TIMEOUT      = 5;
our $READ_TIMEOUT = 15;

use Socket               ();
use Cpanel::UrlTools     ();
use Cpanel::SocketIP     ();
use Cpanel::IP::Loopback ();
use Cpanel::TimeHiRes    ();

sub _setupsocket {
    my ( $self, $host, $addr, $port, $quiet ) = @_;

    if ( exists $self->{'httpsocket'}
        && $self->{'httpsocket'} ) {
        close $self->{'httpsocket'};
    }

    my $connected = 0;
    eval {
        local $SIG{'__DIE__'} = 'DEFAULT';

        local $SIG{'PIPE'} = local $SIG{'ALRM'} = sub {
            print STDERR "..Timeout on connect.." unless $quiet;
            die;
        };

        alarm $TIMEOUT;

        my $proto = getprotobyname('tcp') || do {
            print "..Cannot resolve protocol tcp.." unless $quiet;
            die;
        };
        socket( $self->{'httpsocket'}, Socket::AF_INET, Socket::SOCK_STREAM, $proto ) || do {
            print "..Cannot create socket.." unless $quiet;
            die;
        };
        my $iaddr = Socket::inet_aton("$addr") || do {
            print "...Unable to translate IP address for host: ${host}..." unless $quiet;
            die;
        };
        $port ||= getservbyname( 'http', 'tcp' ) || do {
            print "..Cannot lookup port for http.." unless $quiet;
            die;
        };
        my $sin = Socket::sockaddr_in( $port, $iaddr ) || do {
            print "..ERROR: $! .." unless $quiet;
            die;
        };
        connect( $self->{'httpsocket'}, $sin ) || die "Unable to connect: $!";
        alarm 0;
        $connected = 1;
    };
    alarm 0;
    return $connected;
}

sub timedrequest {    ## no critic(Subroutines::ProhibitExcessComplexity)  -- Refactoring this function is a project, not a bug fix
    my (%REQ) = @_;

    my $url = $REQ{'url'};
    my ( $host, $uri ) = Cpanel::UrlTools::extract_host_uri($url);
    unless ( $host && $uri ) {
        print "Unable to extract host and URI from URL: $url\n" if !$REQ{'quiet'};
        return { 'status' => 0, 'speed' => 0 };
    }

    my $self = {};
    bless $self, __PACKAGE__;

    my $addr;
    if ( $host =~ m/(\d+\.\d+\.d\+\d+)/ ) {
        $addr = $host;
    }
    else {
        $addr = Cpanel::SocketIP::_resolveIpAddress($host);
        if ( !$addr ) {
            print "Unable to resolve $host. Check /etc/resolv.conf\n" if !$REQ{'quiet'};
            return { 'status' => 0, 'speed' => 0 };
        }
    }

    if ( exists $REQ{'nolocal'} && Cpanel::IP::Loopback::is_loopback($addr) ) {
        return { 'status' => 0, 'speed' => 0 };
    }

    if ( !$self->_setupsocket( $host, $addr, $REQ{'port'}, $REQ{'quiet'} ) ) {
        return { 'status' => 0, 'speed' => 0 };
    }

    my $filename;
    my $storef_fh;
    if ( $REQ{'store'} ) {
        if   ( !length $REQ{'filename'} ) { $filename = Cpanel::UrlTools::urltofile($uri); }
        else                              { $filename = $REQ{'filename'}; }
        open( $storef_fh, '>', $filename ) || die "Failed to open “$filename” for writing: $!";
    }

    my $bytes      = 0;
    my $start_time = Cpanel::TimeHiRes::time();
    my $buffer     = '';
    eval {
        local $SIG{'__DIE__'} = 'DEFAULT';
        local $SIG{'PIPE'}    = local $SIG{'ALRM'} = sub {
            print STDERR '..Timeout on receive..' if !$REQ{'quiet'};
            die;
        };

        # In the past we would increase the alarm every time
        # we read from the remote.  Since we only expect to be timing
        # smaller test files we should not keep extending the timeout
        # as it could result in stalling for multiple minutes
        alarm($READ_TIMEOUT);    #set alarm to prevent death
        send $self->{'httpsocket'}, "GET $uri HTTP/1.0\r\nConnection: close\r\nUser-Agent: Cpanel::HttpTimer/$VERSION\r\nHost: $host\r\n\r\n", 0;
        while ( read( $self->{'httpsocket'}, $buffer, 131072, length $buffer ) && length $buffer < $MAX_SIZE ) {
        }
        alarm(0);
    };
    if ($@) {
        print "Error ($@) while fetching url ${url}\n" if !$REQ{'quiet'};
        return { 'status' => 0, 'speed' => 0 };

    }
    $bytes = length $buffer;
    my $end_time = Cpanel::TimeHiRes::time();
    my $telap    = ( $end_time - $start_time );
    $telap ||= 0.00001;    #clock drift
    my $bps = sprintf( "%.2f", ( $bytes / $telap ) );

    my ( $headers, $body ) = split( /\r?\n\r?\n/, $buffer );

    if ( $headers && ( $headers =~ m/SSL-enabled/ || $headers =~ m/location: https:\/\//i ) ) {

        # fall through, we're just here to catch 443 #
    }
    elsif ( $headers && $headers =~ /^HTTP\/\S+\s+(\d+)/ ) {
        my $status = $1;
        if ( $status =~ /^([345]\d+)/ ) {
            print "Error ($status) while fetching url ${url}\n" if !$REQ{'quiet'};
            return { 'status' => 0, 'speed' => 0 };
        }
    }
    else {
        print "Error (no valid headers) while fetching url ${url}\n" if !$REQ{'quiet'};
        return { 'status' => 0, 'speed' => 0 };

    }
    if ( $REQ{'store'} ) {
        print {$storef_fh} $body;
        close($storef_fh);
    }

    if ( $REQ{'return_body'} ) {
        return { 'status' => 1, 'speed' => $bps, 'body' => $body };
    }
    else {
        return { 'status' => 1, 'speed' => $bps };
    }
}

1;
