package Cpanel::SafeRun::Simple;

# cpanel - Cpanel/SafeRun/Simple.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FHUtils::Autoflush ();
use Cpanel::LoadFile::ReadFast ();
use Cpanel::SV                 ();
## no critic qw(TestingAndDebugging::RequireUseWarnings) -- not yet

BEGIN {
    eval { require Proc::FastSpawn; };
}

my $KEEP_STDERR  = 0;
my $MERGE_STDERR = 1;
my $NULL_STDERR  = 2;
my $NULL_STDOUT  = 3;

sub saferun_r {
    return _saferun_r( \@_ );
}

# Warning: Do not pass shell commands to this module.
# as it is intended to prevent callers from accidentally spawning a shell.
#
# We call it saferun because we want it to be safe to use without
# accidentially spawning a shell!
#
# At some point the safeguards that this module was
# originally attempting to prevent from happening (thus the name saferun)
# were removed.
#
# When fast spawn support was added the safeguard were partially restored
#
sub _saferun_r {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ( $cmdline, $error_flag ) = @_;

    if ($Cpanel::AccessIds::ReducedPrivileges::PRIVS_REDUCED) {    # PPI NO PARSE --  can't be reduced if the module isn't loaded
        eval "use Cpanel::Carp;";                                  ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        die Cpanel::Carp::safe_longmess( __PACKAGE__ . " cannot be used with ReducedPrivileges. Use Cpanel::SafeRun::Object instead" );
    }
    elsif ( scalar @$cmdline == 1 && $cmdline->[0] =~ tr{><*?[]`$()|;&#$\\\r\n\t }{} ) {
        eval "use Cpanel::Carp;";                                  ## no critic qw(BuiltinFunctions::ProhibitStringyEval)
        die Cpanel::Carp::safe_longmess( __PACKAGE__ . " prevents accidental execution of a shell.  If you intended to execute a shell use saferun(" . join( ',', '/bin/sh', '-c', @$cmdline ) . ")" );
    }

    my $output;

    # error_flag 0 = errors to STDERR
    # error_flag 1 = errors to STDOUT (saferunallerrors)
    # error_flag 2 = errors to DEVNULL
    # error_flag 3 = errors to STDOUT, STDOUT to DEVNULL (captures only errors, used in saferunonlyerrors)
    if ( index( $cmdline->[0], '/' ) == 0 ) {
        my ($check) = !-e $cmdline->[0] && $cmdline->[0] =~ /[\s<>&\|\;]/ ? split( /[\s<>&\|\;]/, $cmdline->[0], 2 ) : $cmdline->[0];

        if ( !-x $check ) {
            $? = -1;

            #  warn 'Error while executing: [' . join( ' ', @$cmdline ) . ']: file not found';
            return \$output;
        }

        # elsif($cmdline->[0] eq $check && @{$cmdline} == 1 && $cmdline->[0] =~ m/\s/) {
        #     # force array context if we are passing a single binary that has spaces
        #     push @{$cmdline}, "";
        # }
    }
    $error_flag ||= 0;
    local ($/);
    my ( $pid, $prog_fh, $did_fastspawn );

    if ( $INC{'Proc/FastSpawn.pm'} ) {    # may not be available yet due to upcp.static or updatenow.static

        my @env = map { exists $ENV{$_} && $_ ne 'IFS' && $_ ne 'CDPATH' && $_ ne 'ENV' && $_ ne 'BASH_ENV' ? ( $_ . '=' . ( $ENV{$_} // '' ) ) : () } keys %ENV;

        my ($child_write);
        pipe( $prog_fh, $child_write ) or warn "Failed to pipe(): $!";

        my $null_fh;
        if ( $error_flag == $NULL_STDERR || $error_flag == $NULL_STDOUT ) {
            open( $null_fh, '>', '/dev/null' ) or die "Failed open /dev/null: $!";
        }

        Cpanel::FHUtils::Autoflush::enable($_) for ( $prog_fh, $child_write );

        $did_fastspawn = 1;

        my $stdout_fileno = fileno($child_write);
        my $stderr_fileno = -1;

        if ( $error_flag == $MERGE_STDERR ) {
            $stderr_fileno = fileno($child_write);
        }
        elsif ( $error_flag == $NULL_STDERR ) {
            $stderr_fileno = fileno($null_fh);
        }
        elsif ( $error_flag == $NULL_STDOUT ) {
            $stdout_fileno = fileno($null_fh);
            $stderr_fileno = fileno($child_write);
        }

        $pid = Proc::FastSpawn::spawn_open3(
            -1,                # stdin
            $stdout_fileno,    # stdout
            $stderr_fileno,    # stderr
            $cmdline->[0],     # program
            $cmdline,          # args
            \@env,             #env
        );

    }
    else {
        if ( $pid = open( $prog_fh, '-|' ) ) {

        }
        elsif ( defined $pid ) {

            # Remove taint-checked environmental variables; see perlsec.
            delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};

            $ENV{'PATH'} ||= '';
            Cpanel::SV::untaint( $ENV{'PATH'} );

            if ( $error_flag == $MERGE_STDERR ) {
                open( STDERR, '>&STDOUT' ) or die "Failed to redirect STDERR to STDOUT: $!";
            }
            elsif ( $error_flag == $NULL_STDERR ) {
                open( STDERR, '>', '/dev/null' ) or die "Failed to open /dev/null: $!";
            }
            elsif ( $error_flag == $NULL_STDOUT ) {
                open( STDERR, '>&STDOUT' ) or die "Failed to redirect STDERR to STDOUT: $!";
                open( STDOUT, '>', '/dev/null' ) or die "Failed to redirect STDOUT to /dev/null: $!";
            }
            exec(@$cmdline) or exit( $! || 127 );
        }
        else {
            die "fork() failed: $!";
        }
    }
    if ( !$prog_fh || !$pid ) {

        # this if block will never happen, but should it for some reason then set $? to "failure to execute" status
        $? = -1;    ## no critic qw(Variables::RequireLocalizedPunctuationVars)

        # warn 'Error while executing: [' . join( ' ', @$cmdline ) . ']: ' . $!;
        return \$output;
    }
    Cpanel::LoadFile::ReadFast::read_all_fast( $prog_fh, $output );
    close($prog_fh);

    waitpid( $pid, 0 ) if $did_fastspawn;

    # waitpid ($pid, 0); # perldoc -f open: "Closing any piped filehandle causes the parent process to wait for the child to finish, and returns the status value in $?."
    return \$output;
}

sub _call_saferun {
    my ( $args, $flag ) = @_;
    my $ref = _saferun_r( $args, $flag || 0 );

    return $$ref if $ref;
    return;
}

sub saferun {
    return _call_saferun( \@_, $KEEP_STDERR );
}

sub saferunallerrors {
    return _call_saferun( \@_, $MERGE_STDERR );
}

sub saferunnoerror {
    return _call_saferun( \@_, $NULL_STDERR );
}

sub saferunonlyerrors {
    return _call_saferun( \@_, $NULL_STDOUT );
}

1;
