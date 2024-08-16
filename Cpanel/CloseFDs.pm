package Cpanel::CloseFDs;

# cpanel - Cpanel/CloseFDs.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# 6 on a 32bit system. 3 on a 64 bit system.
my $SYS_CLOSE;

BEGIN {
    my $bits = length( pack( 'l!', 1000 ) ) * 8;
    $SYS_CLOSE = ( $bits eq 32 ) ? 6 : 3;
}

#named options:
#   except => an arrayref of (filehandles or file descriptors) NOT to close
#
sub fast_closefds {
    my %opts = @_;

    # If we are running under NYTProf, we cannot closefds
    # because it will close the nytprof.out writer
    if ( $INC{'Devel/NYTProf.pm'} ) { return 0; }

    my @fds_to_except = ( 0 .. 2 );

    if ( $opts{'except'} ) {
        push @fds_to_except, @{ $opts{'except'} };
    }

    my %except;
    for (@fds_to_except) {
        if ( UNIVERSAL::isa( $_, 'GLOB' ) ) {
            my $no = fileno $_;
            next unless defined $no;
            $except{$no} = ();
        }
        else {
            $except{$_} = ();
        }
    }

    my %except_copy = %except;
    delete @except_copy{ ( 0 .. 2 ) };

    if ( !scalar keys %except_copy ) {
        eval {
            local $SIG{'__WARN__'};
            local $SIG{'__DIE__'};
            require IO::CloseFDs;
            IO::CloseFDs::closefds();
        };
    }

    my $read_proc_handles = 0;
    my @handles;
    if ( opendir( my $fd_dh, "/proc/$$/fd" ) ) {
        @handles = grep { !tr{.}{} } readdir($fd_dh);
        closedir $fd_dh;
        $read_proc_handles = 1;
    }
    else {
        @handles = ( 3 .. 1024 );
    }

    for my $fileno (@handles) {
        next if $read_proc_handles && !-e "/proc/$$/fd/$fileno";    # one of these was the opendir
        next if exists $except{$fileno};
        syscall( $SYS_CLOSE, int $fileno );                         #force numeric
    }

    return;
}

sub redirect_standard_io_dev_null {
    open( STDIN,  '<', '/dev/null' );    ## no critic qw(RequireCheckedOpen)
    open( STDOUT, '>', '/dev/null' );    ## no critic qw(RequireCheckedOpen)
    open( STDERR, '>', '/dev/null' );    ## no critic qw(RequireCheckedOpen)

    return;
}

sub fast_daemonclosefds {
    my @args = @_;

    redirect_standard_io_dev_null();
    fast_closefds(@args);

    return;
}

1;
