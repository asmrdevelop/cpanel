package Cpanel::NSCD::Log;

# cpanel - Cpanel/NSCD/Log.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::NSCD::Constants ();
use Cpanel::SafeFile        ();

sub enable_logging_to_file {
    my ( $logfile, $force ) = @_;

    $logfile ||= '/var/log/nscd.log';

    my $lock = Cpanel::SafeFile::safeopen( my $fh, '+<', $Cpanel::NSCD::Constants::NSCD_CONFIG_FILE );
    return 0 unless $lock;

    my @lines = <$fh>;

    my $ret = 0;
    if ( $force || !grep { /^\s*logfile\s+\S+\b/ } @lines ) {
        @lines = grep { !/^\s*(?:logfile|debug-level)\s+/ } @lines;
        push @lines, "logfile $logfile\n";

        # This is required because NSCD will only write to the specified logfile
        # if the debug-level is greater than zero. Otherwise, it will write
        # logging to STDERR, sending it to /var/log/messages.
        push @lines, "debug-level 1";

        seek( $fh, 0, 0 );
        print {$fh} @lines;
        truncate( $fh, tell($fh) );
        $ret = 1;
    }

    Cpanel::SafeFile::safeclose( $fh, $lock );

    return $ret;
}

# This was implemented as a quick-fix for NSCD filling up /var/log/messages
# with noisey log entries. Unfortunately no way is offered to disable the
# logging, so logging to /dev/null will have to suffice.

sub disable_logging {
    return enable_logging_to_file( '/dev/null', 1 );
}

1;
