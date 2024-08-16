package Cpanel::LocalService;

# cpanel - Cpanel/LocalService.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Socket::UNIX::Micro ();
use Cpanel::Socket::Constants   ();

my $try_bind_seconds = 240;    # seconds to try binding to a port before giving up, maybe from config?

sub setupservice {
    my $socket_path = shift;
    my $perms       = shift;
    my $timeout     = shift || $try_bind_seconds;
    my @fds;

    local $SIG{'ALRM'} = sub { die "Socket path unavailable for $timeout seconds, giving up\n" };
    alarm $timeout;

    my $need_bind = 1;

    while ($need_bind) {
        local $^F = 1000;    #prevent cloexec

        my $fd;
        socket( $fd, $Cpanel::Socket::Constants::AF_UNIX, $Cpanel::Socket::Constants::SOCK_STREAM, 0 );
        unlink($socket_path);
        my $socket_addr = Cpanel::Socket::UNIX::Micro::micro_sockaddr_un($socket_path);
        chown 0, 0, $socket_path;

        if (
            bind(
                $fd,
                $socket_addr
            )
        ) {
            if ( listen( $fd, 45 ) && $fd ) {
                select( ( select($fd), $| = 1 )[0] );    ##no critic qw(ProhibitOneArgSelect)  #aka $fd->autoflush(1);

                if ( exists $INC{'IO/Socket/UNIX.pm'} ) {
                    bless $fd, 'IO::Socket::UNIX';
                }

                push @fds, $fd;

                last;                                    # bound
            }
        }

        my $code = int $!;
        sleep(1);
        print STDERR "$0: Waiting to bind to $socket_path ($!)....\n";
    }
    alarm 0;

    chmod $perms, $socket_path;

    return \@fds;
}

1;
