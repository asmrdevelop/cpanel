package Cpanel::SafeRun::Dynamic;

# cpanel - Cpanel/SafeRun/Dynamic.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::SafeRun::Object     ();
use Cpanel::IOCallbackWriteLine ();

our $VERSION = '1.1';

sub saferundynamic {
    my @PROGA = @_;
    return if ( substr( $PROGA[0], 0, 1 ) eq '/' && !-x $PROGA[0] );
    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    open( my $RNULL, '<', '/dev/null' ) or die "Failed to open /dev/null: $!";
    require IPC::Open3;
    my $pid = IPC::Open3::open3( '<&' . fileno($RNULL), ">&STDOUT", ">&STDERR", @PROGA ) || do {
        warn 'Error while executing: [' . join( ' ', @PROGA ) . ']: ' . $!;
        return;
    };
    waitpid( $pid, 0 );
    return;
}

sub livesaferun {
    my %OPTS              = @_;
    my @PROGRAM_WITH_ARGS = @{ $OPTS{'prog'} };
    my $formatter         = $OPTS{'formatter'};
    my $pre_exec_coderef  = $OPTS{'pre_exec_coderef'};
    my $buffer            = $OPTS{'buffer'};

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    return if ( substr( $PROGRAM_WITH_ARGS[0], 0, 1 ) eq '/' && !-x $PROGRAM_WITH_ARGS[0] );
    my $rdr = Symbol::gensym();
    my $pid;
    if ( $pid = open( $rdr, '-|' ) ) {
        my $quit_saferun_loop = 0;
        if ( ref $formatter eq 'CODE' ) {
            while ( ( my $line = readline($rdr) ) ) {
                next if $quit_saferun_loop;
                print $formatter->( $line, \$quit_saferun_loop );
            }
        }
        else {
            if ($buffer) {
                my $buf;
                while ( read( $rdr, $buf, 65535 ) ) {
                    print $buf;
                }
            }
            else {
                print while readline($rdr);
            }
        }
    }
    elsif ( defined $pid ) {
        if ($pre_exec_coderef) { $pre_exec_coderef->(); }
        {
            no strict 'subs';    ## no critic qw(TestingAndDebugging::ProhibitNoStrict)
            open( STDERR, '>&STDOUT' ) or die "Failed to open STDERR to STDOUT: $!";
        }
        exec(@PROGRAM_WITH_ARGS) or exit 1;
    }
    else {
        return;
    }
    close($rdr);
    return;
}

sub saferunnoerrordynamic {
    my @PROGA = @_;
    return if ( substr( $PROGA[0], 0, 1 ) eq '/' && !-x $PROGA[0] );

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    open( my $WNULL, '>', '/dev/null' ) or die "Failed to open /dev/null: $!";
    open( my $RNULL, '<', '/dev/null' ) or die "Failed to open /dev/null: $!";
    require IPC::Open3;
    my $pid = IPC::Open3::open3( '<&' . fileno($RNULL), ">&STDOUT", '>&' . fileno($WNULL), @PROGA ) || do {
        warn 'Error while executing: [' . join( ' ', @PROGA ) . ']: ' . $!;
        return;
    };
    waitpid( $pid, 0 );
    return;
}

# Please use Cpanel::SafeRun::Object directly if you can
# so that you can be more descriptive of failures, which
# saves debugging time.
sub saferun_callback {
    my %OPTS     = @_;
    my @PROGA    = @{ $OPTS{'prog'} };
    my $callback = $OPTS{'callback'};

    return if ( substr( $PROGA[0], 0, 1 ) eq '/' && !-x $PROGA[0] );
    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        die __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead";
    }

    my $program = shift @PROGA;
    my @args    = @PROGA;

    my $quit_saferun_loop = 0;
    my $out_fh            = Cpanel::IOCallbackWriteLine->new(
        sub {
            if ( ref $callback eq 'CODE' ) {
                die if $quit_saferun_loop;
                $callback->( $_[0], \$quit_saferun_loop );
            }
            else {
                print $_[0];
            }
        }
    );

    my $run = Cpanel::SafeRun::Object->new(
        program => $program,
        args    => \@args,
        stdout  => $out_fh,
        stderr  => $out_fh,
    );

    $? = $run->CHILD_ERROR();    # needed for compat

    return;
}

1;
