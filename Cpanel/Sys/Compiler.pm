package Cpanel::Sys::Compiler;

# cpanel - Cpanel/Sys/Compiler.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Logger               ();
use Cpanel::FindBin              ();
use Cpanel::SafeRun::Errors      ();
use Cpanel::CachedCommand::Utils ();
use Cpanel::TempFile             ();
use Cpanel::Rand                 ();
use Cpanel::Tar                  ();
use Cpanel::SafeDir::RM          ();
use Cwd                          ();
use strict;

our $VERSION = '1.9';

my $logger;

sub check_c_compiler {
    my %OPTS     = @_;
    my $verbose  = $OPTS{'verbose'}  || 0;
    my $compiler = $OPTS{'compiler'} || 'gcc';

    if ( -e '/etc/skipccheck' ) {
        return ( 1, "C compiler check disabled per /etc/skipccheck" );
    }

    my @tests = [ $compiler, [] ];

    my $prefered_flags = [];
    my @messages;
    foreach my $test_ref (@tests) {
        my ( $status, $statusmsg, $tuned_status, $tuned_statusmsg, $tuned_flags ) = test_compile( $verbose, @$test_ref );
        return ( 0, [$statusmsg] ) if !$status;
        if ( !-e '/var/cpanel/compileroptimize' ) {
            $tuned_status    = 0;
            $tuned_statusmsg = "Tuned C compiler not available because it is not enabled";
        }
        push @messages, $statusmsg, $tuned_statusmsg;
        $prefered_flags = $tuned_flags if $tuned_status;
    }

    return ( 1, \@messages, $prefered_flags );

}

sub test_compile {
    my $verbose   = shift;
    my $cc        = shift;
    my $flags_ref = shift;
    my $cc_bin    = ( $cc =~ m{^/} ) ? $cc : Cpanel::FindBin::findbin($cc);

    return ( 0, "Could not locate an executable \"$cc\" binary" ) if !$cc_bin;

    my @flags          = ref $flags_ref ? @{$flags_ref} : ();
    my $cc_line        = join( " ", $cc_bin, @flags );
    my $datastore_file = Cpanel::CachedCommand::Utils::_get_datastore_filename( 'Cpanel::Sys::Compiler::test_compile', $cc, @flags );
    $logger ||= Cpanel::Logger->new();
    $logger->info($datastore_file);
    my $binary_mtime = ( stat($cc_bin) )[9];
    if ( !-x _ ) {

        # If they passed us the path we need to check it
        return ( 0, "\"$cc_bin\" is not executable" );
    }
    my $datastore_mtime = ( stat($datastore_file) )[9];
    my $now             = time();
    if ( $datastore_mtime && $datastore_mtime > $binary_mtime && $datastore_mtime < $now && $datastore_mtime > ( $now - 86400 ) ) {
        if ( open( my $datastore_fh, '<', $datastore_file ) ) {
            my $version = readline($datastore_fh);
            chomp($version);
            my $status = readline($datastore_fh);
            chomp($status);
            my $statusmsg = readline($datastore_fh);
            chomp($statusmsg);
            my $tuned_status = readline($datastore_fh);
            chomp($tuned_status);
            my $tuned_statusmsg = readline($datastore_fh);
            chomp($tuned_statusmsg);
            my $tuned_flags = readline($datastore_fh);
            chomp($tuned_flags);
            close($datastore_fh);
            return ( $status, $statusmsg . " (cached " . localtime($datastore_mtime) . ")", $tuned_status, $tuned_statusmsg . " (cached " . localtime($datastore_mtime) . ")", [ split( /\s+/, $tuned_flags ) ] ) if $version eq $VERSION;
        }
        else {
            $logger ||= Cpanel::Logger->new();
            $logger->warn("Could not open compiler datastore file: $datastore_file: $!");
        }
    }
    my $test_bin = Cpanel::TempFile::get_safe_tmpfile($Cpanel::Rand::SKIP_OPEN);

    if ( !$test_bin ) {
        return ( 0, "Failed to create a temporary file for the compiler test" );
    }

    # We do two passes since we attempt to fix up common problems on Linux
    foreach my $pass ( 1 .. 2 ) {

        if ( -e $test_bin . '.c' ) {
            unlink $test_bin . '.c';
            if ( -e $test_bin . '.c' ) {
                return ( 0, "${test_bin}.c still exists after we unlinked it. Unable to verify C compiler." );
            }
        }
        if ( -e $test_bin ) {
            unlink $test_bin;
            if ( -e $test_bin ) {
                return ( 0, "$test_bin still exists after we unlinked it. Unable to verify C compiler." );
            }
        }

        if ( open my $test_c_fh, '>', $test_bin . '.c' ) {

            print {$test_c_fh} <<'EOM';
#include <stdio.h>
#include <sys/types.h>

int main (int argc, char **argv) {
    printf("C Compiler Works\n");
    return 0;
}

EOM
            close $test_c_fh;
        }
        else {
            return ( 0, "Unable to write ${test_bin}.c: $!" );
        }

        my @CMDLINE = ( $test_bin . '.c', '-o', $test_bin );
        if ( scalar @flags ) { unshift @CMDLINE, @flags; }

        print "Running cc " . join( ' ', @CMDLINE ) . "\n" if $verbose;
        my $compile_output = Cpanel::SafeRun::Errors::saferunallerrors( $cc_bin, @CMDLINE );
        chomp $compile_output;

        my $compilerworks = -e $test_bin ? Cpanel::SafeRun::Errors::saferunnoerror($test_bin) : '';
        chomp $compilerworks;

        # Check if the C compiler is broken
        if ( $compilerworks !~ m/C\s+Compiler\s+Works/i ) {
            if ($verbose) {
                print "Compiler broken\n";
                print "Compile output: $compile_output\n";
                print "$test_bin output: $compilerworks\n" if $compilerworks;
            }

            if ( $pass == 1 ) {
                print "Compiler test failed.  Attempting to autorepair compiler.\n";
                system '/usr/local/cpanel/scripts/fixheaders';
                print "Retrying tests.\n";
                next;
            }
            return ( 0, "Could not compile test" );
        }
        else {
            my $tuned_ccline          = '';
            my $tuned_flags           = [];
            my $tuned_compiler_status = 0;
            my $tuned_compiler_msg;

            print "C compiler ($cc_line) OK\n" if $verbose;

            my %GCC_FLAGS = map { $_ => undef } qw(mmx sse sse2 sse3 ssse3 sse4a sse4.1 sse4.2 sse5 avx aes pclmul sgsbase rdrnd f16c xop lwp 3dnow popcnt abm bmi tbm);

            foreach my $tune_types ( 'native', '_dynamic_' ) {
                unlink $test_bin;

                my @TUNE_FLAGS;
                if ( $tune_types eq 'native' ) {
                    @TUNE_FLAGS = '-march=native';
                }
                elsif ( $tune_types eq '_dynamic_' ) {
                    if ( open( my $cpu_info_fh, '<', '/proc/cpuinfo' ) ) {
                        local $/;
                        my %OPTS = map { ( split( /\s*:\s*/, $_, 2 ) )[ 0, 1 ] } split( /\n/, readline($cpu_info_fh) );
                        foreach my $cpuflag ( split( /\s+/, $OPTS{'flags'} ) ) {
                            $cpuflag = "sse3" if $cpuflag eq "pni";
                            $cpuflag =~ s/sse4_(\d)/sse_4.$1/;
                            if ( exists $GCC_FLAGS{$cpuflag} ) {
                                push @TUNE_FLAGS, '-m' . $cpuflag;
                            }

                            # Case 54333: this would break Template tool kit because of a bug in Makefile.PL
                            # if ( $cpuflag eq 'sse' ) {
                            #     push @TUNE_FLAGS, '-mfpmath=sse';
                            # }
                        }
                    }
                    else {
                        my $has_sse = `/sbin/sysctl hw.instruction_sse 2>&1`;
                        if ( $has_sse =~ m/hw.instruction_sse:\s+1/ ) {

                            # Case 54333: this would break Template tool kit because of a bug in Makefile.PL
                            # push @TUNE_FLAGS, '-mfpmath=sse', '-msse';
                            push @TUNE_FLAGS, '-msse';
                        }
                    }
                }

                my @CMDLINE = ( $test_bin . '.c', '-o', $test_bin );
                if ( scalar @flags ) { unshift @CMDLINE, @flags; }
                unshift @CMDLINE, @TUNE_FLAGS;

                print "Running cc " . join( ' ', @CMDLINE ) . "\n" if $verbose;
                my $tuned_compile_output = Cpanel::SafeRun::Errors::saferunallerrors( $cc_bin, @CMDLINE );
                chomp $tuned_compile_output;

                my $tuned_compilerworks = -e $test_bin ? Cpanel::SafeRun::Errors::saferunnoerror($test_bin) : '';
                chomp $tuned_compilerworks;

                $tuned_flags           = \@TUNE_FLAGS;
                $tuned_ccline          = join( " ", $cc_bin, @TUNE_FLAGS, @flags );
                $tuned_compiler_status = ( $tuned_compilerworks =~ m/C\s+Compiler\s+Works/i ) ? 1 : 0;
                $tuned_compiler_msg    = ( $tuned_compiler_status ? "Tuned C compiler ($tuned_ccline) OK" : "Tuned C compiler ($tuned_ccline) Not available" );
                last if $tuned_compiler_status;
            }

            # Clean up test code and binary
            unlink $test_bin . '.c';
            unlink $test_bin;

            if ( open( my $datastore_fh, '>', $datastore_file ) ) {
                print {$datastore_fh} "$VERSION\n1\nC compiler ($cc_line) OK\n$tuned_compiler_status\n$tuned_compiler_msg\n" . join( " ", @{$tuned_flags} );
                close($datastore_fh);
            }
            return ( 1, "C compiler ($cc_line) OK", $tuned_compiler_status, $tuned_compiler_msg, $tuned_flags );
        }
    }
}

# Check for Sandy Bridge processor + libc AVX bug
# http://sourceware.org/bugzilla/show_bug.cgi?format=multiple&id=12113
our $sb_test_tarball = '/usr/local/cpanel/src/3rdparty/gpl/sandy_bridge_test.tar.gz';

sub check_for_sandy_bridge_bug {
    my $cwd     = Cwd::getcwd();
    my $tar_cfg = Cpanel::Tar::load_tarcfg();
    my $dir     = Cpanel::TempFile::get_safe_tmpdir();
    chdir($dir) or return -1;
    Cpanel::SafeRun::Errors::saferunallerrors( $tar_cfg->{'bin'}, '-x', '-z', '-f', $sb_test_tarball );
    if ( $? >> 8 ) {

        # failed to extract properly
        chdir($cwd);
        Cpanel::SafeDir::RM::safermdir($dir);
        return -1;
    }

    Cpanel::SafeRun::Errors::saferunallerrors( 'make', 'test' );
    my $result = ( $? >> 8 ) ? 1 : 0;
    chdir($cwd);
    Cpanel::SafeDir::RM::safermdir($dir);
    return $result;
}

1;
