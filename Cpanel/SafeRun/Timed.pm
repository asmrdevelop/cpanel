package Cpanel::SafeRun::Timed;

# cpanel - Cpanel/SafeRun/Timed.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.1';

sub timedsaferun {
    my ( $timer, @PROGA ) = @_;

    return _timedsaferun( $timer, 0, @PROGA );
}

sub timedsaferun_allerrors {
    my ( $timer, @PROGA ) = @_;

    return _timedsaferun( $timer, 1, @PROGA );
}

sub _timedsaferun {
    my ( $timer, $stderr_to_stdout, @PROGA ) = @_;
    return if ( substr( $PROGA[0], 0, 1 ) eq '/' && !-x $PROGA[0] );
    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    my $output;
    my $complete = 0;
    my $pid;
    my $fh;                                                        # Case 63723: must declare $fh before eval block in order to avoid unwanted implicit waitpid on die
    eval {
        local $SIG{'__DIE__'} = 'DEFAULT';
        local $SIG{'ALRM'}    = sub { die "Timeout while executing: " . join( ' ', @PROGA ) . "\n"; };
        alarm($timer);
        if ( $pid = open( $fh, '-|' ) ) {
            local $/;
            $output = readline($fh);
            close($fh);
        }
        elsif ( defined $pid ) {
            open( STDIN, '<', '/dev/null' );
            if ($stderr_to_stdout) {
                open( STDERR, '>&', 'STDOUT' );
            }
            exec(@PROGA) or exit 1;
        }
        else {
            warn 'Error while executing: [' . join( ' ', @PROGA ) . ']: ' . $!;
            alarm(0);
            return;
        }
        $complete = 1;
        alarm 0;
    };
    if ($@) {
        $output .= $@;
    }
    alarm 0;
    if ( !$complete && $pid && $pid > 0 ) {
        kill( 15, $pid );    #TERM
        sleep(1);            # Give the process a chance to die 'nicely'
        kill( 9, $pid );     #KILL
    }
    return $output;
}

1;
