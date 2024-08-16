package Cpanel::CpuWatch;

# cpanel - Cpanel/CpuWatch.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ChildErrorStringifier ();
use Cpanel::ConfigFiles           ();
use Cpanel::Cpu                   ();
use Cpanel::Exception             ();
use Cpanel::FHUtils::FDFlags      ();
use Cpanel::JSON                  ();
use Cpanel::SafeRun::Object       ();
use Cpanel::TempFile              ();

our $PERCENT_LOAD_TO_START_CURTAILMENT = 0.875;

#----------------------------------------------------------------------
#These two functions run the “cpuwatch” command, with or without rlimits.
#
#They pass a system load to that command that corresponds with the result of
#Cpanel::Cpu::getcpucount(), which factors in the “extracpus” config value.
#
#These both take named arguments that match with Cpanel::SafeRun::Object:
#   program     (required)
#   args        (optional)
#   stdout      (optional)
#   stderr      (optional)
#   after_fork  (optional)
#   keep_env    (optional)
#
#(Note that “before_exec” isn’t in the above list … this is by design.)
#
#An appropriate exception will be thrown under any of these circumstances:
#   - failed to execute cpuwatch/logrunner
#   - cpuwatch/logrunner errored
#   - the given “program” errored
#
sub run             { return _run( @_, command => 'cpuwatch' ) }
sub run_with_rlimit { return _run( @_, command => 'logrunner' ) }

sub _run {
    my (%opts) = @_;

    die "before_exec() prevents fastspawn; don’t use it!" if $opts{'before_exec'};

    my $temp_obj = Cpanel::TempFile->new();

    my ( $tfile, $tfh ) = $temp_obj->file();
    Cpanel::FHUtils::FDFlags::set_non_CLOEXEC($tfh);

    my $runner_cmd = "$Cpanel::ConfigFiles::CPANEL_ROOT/bin/$opts{'command'}";

    my $max_load = sprintf( "%.4f", scalar Cpanel::Cpu::getcpucount() * $PERCENT_LOAD_TO_START_CURTAILMENT );

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => $runner_cmd,
        args    => [
            $max_load,
            '--report-fd' => fileno($tfh),
            $opts{'program'},
            ( $opts{'args'} ? @{ $opts{'args'} } : () ),
        ],
        timeout      => 86400,
        read_timeout => 0,

        #“before_exec” isn’t in the list below because it
        #would prevent SafeRun::Object from using fastspawn.
        (
            map { ( $_ => $opts{$_} ) }
              qw(
              stdout
              stderr
              after_fork
              keep_env
              )
        ),
    );

    if ( !-s $tfile ) {
        die Cpanel::Exception->create( 'The command “[_1]” failed to report errors to the status file.', [$runner_cmd] );
    }
    my $forked_process_autopsy = Cpanel::JSON::LoadFile($tfile);
    if ( $forked_process_autopsy->{'exec_errno'} ) {
        my $err_str = do { local $! = $forked_process_autopsy->{'exec_errno'} };
        die Cpanel::Exception::create( 'IO::ExecError', [ path => $opts{'program'}, error => $err_str ] );
    }

    if ( $forked_process_autopsy->{'waitpid_status'} ) {
        my $err_obj = Cpanel::ChildErrorStringifier->new( $forked_process_autopsy->{'waitpid_status'} );

        if ( $err_obj->signal_code() ) {
            die Cpanel::Exception::create(
                'ProcessFailed::Signal',
                [
                    process_name => $opts{'program'},
                    signal_code  => $err_obj->signal_code(),
                    $opts{'stdout'} ? () : ( stdout => $run->stdout() ),
                    $opts{'stderr'} ? () : ( stderr => $run->stderr() ),
                ]
            );
        }

        die Cpanel::Exception::create(
            'ProcessFailed::Error',
            [
                process_name => $opts{'program'},
                error_code   => $err_obj->error_code(),
                $opts{'stdout'} ? () : ( stdout => $run->stdout() ),
                $opts{'stderr'} ? () : ( stderr => $run->stderr() ),

            ]
        );
    }

    return $run;
}

1;
