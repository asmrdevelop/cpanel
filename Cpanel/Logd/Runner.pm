package Cpanel::Logd::Runner;

# cpanel - Cpanel/Logd/Runner.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Logd::Runner - Command runner for cpanellogd

=head1 METHODS

=cut

use strict;

use Try::Tiny;

use Cpanel::CPAN::IO::Callback::Write ();

use Cpanel::CpuWatch                 ();
use Cpanel::StringFunc::LineIterator ();

my $MAX_INPUT_FROM_COMMAND = 8_192;

=pod

B<run( %opts )>

This executes a command via “logrunner”, which ensures that
the process doesn’t eat up undue system resources.

This function also sends all STDOUT and STDERR from the executed command
into the given StatsLog object.

This will die() with an appropriate exception object
if the command can’t run or ends in error.

Named args:

=over 4

=item * program (required, string)

=item * args (optional, array ref)

=item * logger (required, a C<Cpanel::Logd::StatsLog> instance)

=back

Returns: a C<Cpanel::SafeRun::Object> instance

=cut

sub run {
    my (%opts) = @_;

    my $program = $opts{'program'};
    if ( !length $program ) {
        die "Need “program”!";
    }

    if ( !try { $opts{'logger'}->isa('Cpanel::Logd::StatsLog') } ) {
        die "“logger” must be a Cpanel::Logd::StatsLog, not “$opts{'logger'}”!";
    }

    my @args = $opts{'args'} ? @{ $opts{'args'} } : ();

    my $cmd_str = join( ' ', $program, @args );

    my $readbytes = 0;
    $opts{'logger'}->log( 3, "exec: [$cmd_str]" );

    my $read_buffer = q<>;

    my $out_fh = Cpanel::CPAN::IO::Callback::Write->new(
        sub {
            if ( $readbytes <= $MAX_INPUT_FROM_COMMAND ) {
                $readbytes += length( $_[0] );

                $read_buffer .= $_[0];

                my $iter;
                Cpanel::StringFunc::LineIterator->new(
                    $read_buffer,
                    sub {
                        $iter ||= shift;

                        #Leave partial lines in place.
                        chomp or $iter->stop();

                        $iter->replace_with(q<>);

                        $opts{'logger'}->log( 1, $_ );
                    },
                );

                if ( $readbytes >= $MAX_INPUT_FROM_COMMAND ) {
                    $opts{'logger'}->log( 1, "cpanellogd: too many errors ... truncating output from [$cmd_str]" );
                }
            }
        }
    );

    # We set certain parameters for awstats via environment variables
    # The CpuWatch mechanism cleans the environment, by default
    # so we must set keep_env

    my $run = Cpanel::CpuWatch::run_with_rlimit(
        program  => $program,
        args     => \@args,
        stdout   => $out_fh,
        stderr   => $out_fh,
        keep_env => 1,
    );

    #Write any remaining text to the log.
    if ( $readbytes <= $MAX_INPUT_FROM_COMMAND && length $read_buffer ) {
        $opts{'logger'}->log( 1, $read_buffer );
    }

    return $run;
}

1;
