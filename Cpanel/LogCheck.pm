package Cpanel::LogCheck;

# cpanel - Cpanel/LogCheck.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $log_dir = '/usr/local/cpanel/logs';

sub logcheck {
    -e $log_dir or die <<EOE;

*** $0 ERROR: ***
    Refusing to start because log directory $log_dir doesn't exist!
    Please create the $log_dir directory and try again.

EOE
}

sub logcheck_writable {
    logcheck();

    require Fcntl;

    my $test_file = "$log_dir/test_write";
    my $writable  = eval {
        sysopen my $fh, $test_file, Fcntl::O_CREAT() | Fcntl::O_WRONLY() | Fcntl::O_TRUNC() | Fcntl::O_NOFOLLOW() or die $!;
        print {$fh} "#########################" or die $!;    # in disk full conditions, open and close will still succeed if no data is written
        close $fh                               or die $!;
    };
    my $error = $@;
    unlink $test_file if -e $test_file;
    if ( !$writable ) {
        die <<EOE;

*** $0 ERROR: ***
    Refusing to start because log directory $log_dir is not writable!
    The specific error was: $error
    Please rectify this problem and then try again.

EOE
    }
}

1;

__END__

=head1 SYNOPSIS

use Cpanel::LogCheck ();

Cpanel::LogCheck::logcheck(); # Will die with an informative message if the log directory doesn't exist

        - or -

Cpanel::LogCheck::logcheck_writable(); # Will die with an informative message if logs cannot be written

=head1 DESCRIPTION

The purpose of this module is to allow various startup scripts to check
for a usable log directory without replicating the check and messages
everywhere.
