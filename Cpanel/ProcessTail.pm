#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/ProcessTail.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ProcessTail;

use strict;
use warnings;
use Time::HiRes           ();
use Cpanel::Encoder::JSON ();

our $sleeptime   = 250_000;
our $sleeptime_1 = 100_000;
my %HTML_ENCODE_MAP = ( '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;' );

sub _cleanse {
    my $data = shift;
    $data =~ s/([&<>"'])/$HTML_ENCODE_MAP{$1}/sg;
    $data =~ s/ /\&nbsp;/g;
    $data =~ s/[\r\n]/<br>\n/g;
    return $data;
}

sub print_log_line {
    my $line = shift;

    if ( $line =~ s/\[.*\]\s+updateParent_.*_.*_.*_js \(([a-z0-9]*) ([a-z0-9]*) ([a-z0-9]*)\)\n//g ) {
        my ( $from, $status, $cmd ) = map { pack 'h*', $_ } ( $1, $2, $3 );
        my $str_json = Cpanel::Encoder::JSON::json_encode_str("[$from] $status : $cmd ");
        print qq{\n<script type="text/javascript">parent.update_ui_status($str_json)</script>\n};
    }
    elsif ( $line =~ s/\[.*\]\s+(\d+)\%\scomplete.*\n//g ) {
        my $per = $1;
        print qq(<script type="text/javascript">parent.update_percent($per);</script>\n);
        if ( $per >= 100 ) {
            print qq{\n<script type="text/javascript">logFinished();</script>\n};
        }
    }
    elsif ( $line =~ m/\[.*\]\s+Processing\:\s+(.+)\.*[\r\n]*/ ) {
        my $str_json = Cpanel::Encoder::JSON::json_encode_str("$1.");
        print qq(<script type="text/javascript">parent.update_ui_status($str_json);</script>\n);
    }

    print _cleanse($line);
    return;
}

sub process_log {
    my ( $fh, $check_warnings, $log, $pid_cr ) = @_;

    my $incomplete_line;
    my $curpos       = tell($fh);
    my $need_to_read = 2;
    while ( $need_to_read-- > 0 ) {
        seek( $fh, $curpos, 0 );    # this clears the eof flag on the filehandle
        while ( my $line = readline($fh) ) {
            if ( defined $incomplete_line ) {
                $line            = $incomplete_line . $line;
                $incomplete_line = undef;
            }
            if ( $line !~ m/\n$/ ) {
                $incomplete_line = $line;
                next;
            }
            if ( $check_warnings && $line =~ /\[.*\]\s+W\s+previous\s+PID.*has\s+been\s+running\s+more\s+than\s+/ ) {
                $check_warnings = undef;

                # leave some time to be able to get ea4 migration pid ( logger created before pid file )
                for ( 1 .. 5 ) {
                    last if -e $log;
                    Time::HiRes::usleep($sleeptime);
                }
            }
            Cpanel::ProcessTail::print_log_line($line);
        }
        $curpos = tell($fh);
        Time::HiRes::usleep($sleeptime_1);    # Sleep .1 seconds
                                              # give it one extra loop
        $need_to_read = 2 if -e $log && $pid_cr->();
    }

    print_log_line($incomplete_line) if defined $incomplete_line;
    return;
}

1;
