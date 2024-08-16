
# cpanel - Cpanel/Install/Utils/Command.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Install::Utils::Command;

use strict;
use warnings;

use Cpanel::Install::Utils::Logger ();
use Cpanel::TimeHiRes              ();
use Cpanel::IOCallbackWriteLine    ();
use Cpanel::SafeRun::Object        ();

our $yumcheck = 0;

=encoding utf-8

=head1 NAME

Cpanel::Install::Utils::Command - Run and log system commands for the cpanel base install

=head1 SYNOPSIS

    use Cpanel::Install::Utils::Command;

    Cpanel::Install::Utils::Command::ssystem_with_retry(@cmd);
    Cpanel::Install::Utils::Command::ssystem(@cmd);

=cut

=head2 ssystem_with_retry(@cmd)

Run and log a system command until it exits with
a zero status up to five times.

This method is most commonly used when the system
command is a call to yum.

=cut

sub ssystem_with_retry {
    my @cmd = @_;

    my $ret;
    for my $attempts ( 1 .. 5 ) {
        $ret = ssystem(@cmd);
        return $ret if $ret == 0;
        last        if $attempts == 5;
        Cpanel::Install::Utils::Logger::INFO("Retrying execution of “@cmd”");
        Cpanel::TimeHiRes::sleep(0.25);
    }
    return $ret;
}

=head2 ssystem(@cmd)

Run and log a system command.

If $yumcheck is set to 1 and the phrase 'yum might be hung' is
detected in the output the command will be terminated.  This is
most useful when called via ssystem_with_retry() since it allows
the system to retry yum commands that fail.

=cut

sub ssystem {
    my (@cmd) = @_;
    my ( $program, @args ) = @cmd;
    my $start_time = Cpanel::TimeHiRes::time();

    Cpanel::Install::Utils::Logger::DEBUG( '- ssystem [BEGIN]: ' . join( ' ', @cmd ) );

    my $pid;
    my $output_obj = Cpanel::IOCallbackWriteLine->new(
        sub {
            my ($line) = @_;
            $line =~ tr{\r}{}d;    # Strip ^M from output for better log output.

            if ( $yumcheck && $line =~ /yum might be hung/ ) {
                kill 15, $pid;
                sleep 2;
                Cpanel::Install::Utils::Logger::WARN("....yum is hung, trying to restart it....");
                system(qw/killall -TERM yum/);
                sleep(20);
                system(qw/killall -TERM yum/);
            }

            Cpanel::Install::Utils::Logger::DEBUG( "  " . $line );

            return;
        }
    );
    my $run = Cpanel::SafeRun::Object->new(
        'program'    => $program,
        'args'       => \@args,
        'after_fork' => sub { $pid = $_[0]; },
        'stdout'     => $output_obj,
        'stderr'     => $output_obj,
    );

    my $exit_status = $run->error_code() // 0;

    # We do not ignore exit_status, we only ignore signals
    Cpanel::Install::Utils::Logger::DEBUG("  - ssystem [EXIT_CODE] '$cmd[0]' exited with $exit_status") if ($exit_status);

    if ( my $signal_code = $run->signal_code() ) {
        Cpanel::Install::Utils::Logger::WARN("  - ssystem [SIGNAL_CODE] '$cmd[0]' exited with signal $signal_code (ignored)");
    }

    Cpanel::Install::Utils::Logger::DEBUG('- ssystem [END]');
    my $end_time  = Cpanel::TimeHiRes::time();
    my $exec_time = sprintf( "%.3f", ( $end_time - $start_time ) );
    Cpanel::Install::Utils::Logger::INFO("Completed execution of “@cmd” in $exec_time second(s)");

    return $exit_status;
}

1;

__END__
