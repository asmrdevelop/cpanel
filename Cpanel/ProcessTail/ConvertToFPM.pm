#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/ProcessTail/ConvertToFPM.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ProcessTail::ConvertToFPM;

use strict;
use warnings;

use Cpanel::ProcessTail;
use Cpanel::CloseFDs        ();
use IO::Handle              ();
use Time::HiRes             ();
use Cpanel::Encoder::Tiny   ();
use Cpanel::Unix::PID::Tiny ();

=head1 NAME

Cpanel::ProcessTail::ConvertToFPM

=head1 SYNOPSIS

use Cpanel::ProcessTail::ConvertToFPM;

$convert->run_tail ( $params_hr );

=head1 DESCRIPTION

Provides a cgi tailer backend used while calling the API to convert
all the domains on the system to PHP-FPM.

=head1 METHODS

=head2 run_tail

The superstructure of the ProcessTail system calls into run_tail to
get the lines of the log produced by the conversion of all domains
to PHP-FPM.

=over 3

=item C<< $params_hr >>

The values passed in via the URL, the needed parameters are the following:

'process' => 'ConvertToFPM'
'build_id' => build_id which is used to find the correct log

=back

B<Returns>: Returns nothing, but output's the contents of the log
to STDOUT which is sent downstream to the browser.

=cut

sub log_it {
    my ($msg) = @_;

    print $msg;

    return;
}

our $log_dir = '/var/cpanel/logs';
our $pid_from_log;

sub run_tail {
    my ( $self, $params_hr ) = @_;

    if ( !defined( $params_hr->{'build_id'} ) || $params_hr->{'build_id'} !~ m/^[0-9]+$/ ) {
        log_it("Invalid build_id received.");
        return;
    }

    my $build_id = $params_hr->{'build_id'};

    my $log_file = $log_dir . '/convert_all_domains_to_fpm.' . $build_id . '.log';

    log_it(qq{<script type="text/javascript">statusbox_modal=0;</script>\n});
    Cpanel::CloseFDs::fast_closefds();

    my $current_update_log = $log_file;
    my $max                = 60;
    my $iter               = 0;

    # build_id must be checked after having a log
    #    in most cases except when a process is running for more than 6 hours...
    my $check_warnings = !-e $current_update_log;
    if ($check_warnings) {
        Cpanel::ProcessTail::print_log_line("The convert to PHP-FPM process cannot be found. This will be the output from the last run.\n");
    }

    # Get PID from log of $build_id
    if ( open( my $log_fh, '<', "$current_update_log" ) ) {
        my $pid_line = <$log_fh>;
        if ( $pid_line =~ m/CHILD_PID\:\s(\d+)/ ) {
            $pid_from_log = $1;
        }
        close($log_fh);
    }

    # Wait till we're allowed to open it.
    my $fh;
    until ( defined $fh && fileno $fh ) {
        $fh = IO::Handle->new();
        if ( !open $fh, '<', $current_update_log ) {
            undef $fh;
            Time::HiRes::usleep($Cpanel::ProcessTail::sleeptime);    # sleep just a bit

            # try to open the last log file several times
            #    let some time for ea4 migration to start
            if ( ++$iter > $max ) {
                log_it( '<p>Unable to find log file: ' . Cpanel::Encoder::Tiny::safe_html_encode_str($log_file) . '</p>' );
                return;
            }
        }
    }

    # avoid an infinite loop when the build_id file exists
    #    and is not going to be removed
    my $upid = Cpanel::Unix::PID::Tiny->new();

    Cpanel::ProcessTail::process_log( $fh, $check_warnings, $current_update_log, sub { return $upid->is_pid_running($pid_from_log) } );
    log_it("</pre>\n");
    log_it("<div id='endOfLog'></div>\n");
    log_it(qq{\n<script type="text/javascript">logFinished();</script>\n});
    return;

}

1;
