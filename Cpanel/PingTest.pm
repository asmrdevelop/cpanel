package Cpanel::PingTest;

# cpanel - Cpanel/PingTest.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use IO::Poll                      ();
use IO::Handle                    ();
use Cpanel::IOPollCompat          ();                 # PPI USE OK - add methods to IO::Poll namespace
use Cpanel::TimeHiRes             ();
use Socket                        ();
use Cpanel::Sys::Hardware::Memory ();
use Cpanel::Sys::Rlimit           ();
use Cpanel::ArrayFunc             ();
use Cpanel::Alarm                 ();
use Errno                         qw(ECONNREFUSED);

use constant {
    _DEAD_HOST_TIME => 1000,    # seconds
    _DEFAULT_PORT   => 80,
    _PING_TIMEOUT   => 5,       # 5 seconds since tcp is faster

    _MIN_AVAILABLE_MEMORY => 256,     # Note this is "available", not "installed" system memory, in MB
    _PERCENTAGE_OF_LIMIT  => 0.75,    # Arbitrary, but try to keep a user below their NPROC limits

    _MIN_CHILDREN   => 2,
    _FEWER_CHILDREN => 12,            # When available memory < _MIN_AVAILABLE_MEMORY
    _MAX_CHILDREN   => 50,
};

sub pinghosts {
    my ( $rHOSTLIST, $port ) = @_;

    # default to 80 #
    $port ||= _DEFAULT_PORT;

    my $child        = 0;
    my $poll         = IO::Poll->new();
    my $max_children = _get_max_children();

    my %FD_HOST_MAP;
    my %FD_PID_MAP;
    my %PINGTIMES;

    while ( my $host = shift( @{$rHOSTLIST} ) ) {
        while ( $child > $max_children ) {
            do_poll( $poll, \$child, \%PINGTIMES, \%FD_HOST_MAP, \%FD_PID_MAP );
        }

        my $np_fh = IO::Handle->new();
        my $pid   = open( $np_fh, '-|' );
        next if !defined $pid;

        $np_fh->blocking(0);
        if ($pid) {
            $FD_HOST_MAP{ fileno($np_fh) } = $host;
            $FD_PID_MAP{ fileno($np_fh) }  = $pid;
            $poll->mask( $np_fh => IO::Poll::POLLIN | IO::Poll::POLLHUP | IO::Poll::POLLNVAL | IO::Poll::POLLERR );
            $child++;
            print '.' if !$ENV{'TAP_COMPLIANT'};
        }
        else {
            pinghost( $host, $port );
            exit;
        }
    }

    while ($child) {
        do_poll( $poll, \$child, \%PINGTIMES, \%FD_HOST_MAP, \%FD_PID_MAP );
    }
    return \%PINGTIMES;
}

sub do_poll {
    my ( $poll, $rchild, $rPINGTIMES, $rFD_HOST_MAP, $rFD_PID_MAP ) = @_;
    if ( $poll->poll(0.5) ) {
        my @readyfds = $poll->handles( IO::Poll::POLLIN | IO::Poll::POLLHUP | IO::Poll::POLLNVAL | IO::Poll::POLLERR );
        foreach my $fd (@readyfds) {
            my $fileno = fileno($fd);
            my $host   = $rFD_HOST_MAP->{$fileno};
            while ( readline($fd) ) {
                if (/[\d\.]+\/([\d\.]+)/) {
                    $rPINGTIMES->{$host} = $1;
                }
            }
        }
        @readyfds = $poll->handles( IO::Poll::POLLHUP | IO::Poll::POLLNVAL | IO::Poll::POLLERR );
        foreach my $fd (@readyfds) {
            my $fileno = fileno($fd);
            my $host   = $rFD_HOST_MAP->{$fileno};
            my $pid    = $rFD_PID_MAP->{$fileno};

            if ( !exists $rPINGTIMES->{$host} ) { $rPINGTIMES->{$host} = _round_time(_DEAD_HOST_TIME); }
            delete $rFD_HOST_MAP->{$fileno};
            delete $rFD_PID_MAP->{$fileno};
            $poll->remove($fd);
            $poll->forced_remove($fd);
            close($fd);

            $$rchild--;

            waitpid( $pid, 1 );
        }
    }
    return;
}

sub pinghost {
    my ( $host, $port ) = @_;

    $port ||= _DEFAULT_PORT;

    my $iaddr = Socket::inet_aton($host)             or deadhost();
    my $proto = getprotobyname('tcp')                or deadhost();
    my $paddr = Socket::sockaddr_in( $port, $iaddr ) or deadhost();
    socket( my $test_fh, Socket::PF_INET, Socket::SOCK_STREAM, $proto ) or deadhost();

    my $alarm      = Cpanel::Alarm->new( _PING_TIMEOUT, sub { deadhost() } );
    my $start_time = Cpanel::TimeHiRes::time();
    my $end_time;
    if ( connect( $test_fh, $paddr ) || $! == ECONNREFUSED ) {
        $end_time = Cpanel::TimeHiRes::time();
    }
    close($test_fh);
    undef $alarm;

    deadhost() unless defined $end_time;

    _print_time( $end_time - $start_time );
    exit 0;
}

sub deadhost {
    _print_time(_DEAD_HOST_TIME);
    exit 1;
}

sub _print_time {
    my $time = _round_time(shift);
    print $time . '/' . $time;    # do_poll() expects this pattern
    return;
}

sub _round_time {

    # Round the string representation of the timestamp to microseconds.
    # Printing more precision than this is unnecessary and likely bogus due to system timing inaccuracies.
    return sprintf( '%.6f', $_[0] );
}

sub _get_max_children {
    return Cpanel::ArrayFunc::max(
        _MIN_CHILDREN,
        Cpanel::ArrayFunc::min(
            _MAX_CHILDREN,
            Cpanel::Sys::Hardware::Memory::get_available() < _MIN_AVAILABLE_MEMORY ? _FEWER_CHILDREN : (),
            map { int( $_ * _PERCENTAGE_OF_LIMIT ) } Cpanel::Sys::Rlimit::getrlimit('NPROC'),    # Hard and soft user process limits
        ),
    );
}

1;
