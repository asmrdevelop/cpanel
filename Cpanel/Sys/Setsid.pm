package Cpanel::Sys::Setsid;

# cpanel - Cpanel/Sys/Setsid.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- This code is used in dormant services

# No deps for dormant mode
# This will fully daemonize any following code.
# The double fork and setsid call will detach any tty's

my $SETSID = 112;

sub full_daemonize {
    my $opts = shift;

    my $pid = fork();

    if ( !defined $pid ) {
        die $INC{'Cpanel/Exception.pm'} ? Cpanel::Exception::create( 'IO::ForkError', [ error => $! ] ) : "Failed to fork: $!";
    }
    elsif ($pid) {
        if ( $opts->{'keep_parent'} ) {
            waitpid( $pid, 0 );
            return $pid;
        }
        else {
            exit;
        }
    }
    else {
        my $ret = CORE::syscall($SETSID);
        if ( ( $ret == -1 ) && $! ) {
            die $INC{'Cpanel/Exception.pm'} ? Cpanel::Exception::create( 'SystemCall', [ name => 'setsid', error => $!, arguments => [] ] ) : "Failed system call “setsid”: $!";
        }

        my $cpid = fork();

        if ( !defined $cpid ) {
            die $INC{'Cpanel/Exception.pm'} ? Cpanel::Exception::create( 'IO::ForkError', [ error => $! ] ) : "Failed to fork: $!";
        }
        elsif ($cpid) {
            waitpid( $cpid, 0 ) if $opts->{'keep_parent'};
            my $ec = $? >> 8;
            exit $ec;
        }
        else {
            return $cpid;
        }
    }
}

1;
