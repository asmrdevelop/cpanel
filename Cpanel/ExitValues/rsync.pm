package Cpanel::ExitValues::rsync;

# cpanel - Cpanel/ExitValues/rsync.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::ExitValues::rsync - exit values utility for the “rsync” utility

=head1 SYNOPSIS

    use Cpanel::ExitValues::rsync ();

    my $rsync_exit = 6;

    if (!Cpanel::ExitValues::rsync->error_is_nonfatal_for_cpanel($rsync_exit)) {
        my $pretty_err = Cpanel::ExitValues::rsync->number_to_string($rsync_exit);
    }

=cut

use strict;

use parent qw(
  Cpanel::ExitValues
);

#These are error codes that cPanel deems not to be error conditions.
#
sub _CPANEL_NONFATAL_ERROR_CODES {
    return qw(
      23
      24
    );
}

#cf. https://download.samba.org/pub/rsync/rsync.html
sub _numbers_to_strings {
    return (
        0  => 'Success',
        1  => 'Syntax or usage error',
        2  => 'Protocol incompatibility',
        3  => 'Errors selecting input/output files, dirs',
        4  => 'Requested action not supported: an attempt was made to manipulate 64-bit files on a platform that cannot support them; or an option was specified that is supported by the client and not by the server.',
        5  => 'Error starting client-server protocol',
        6  => 'Daemon unable to append to log-file',
        10 => 'Error in socket I/O',
        11 => 'Error in file I/O',
        12 => 'Error in rsync protocol data stream',
        13 => 'Errors with program diagnostics',
        14 => 'Error in IPC code',
        20 => 'Received SIGUSR1 or SIGINT',
        21 => 'Some error returned by waitpid()',
        22 => 'Error allocating core memory buffers',
        23 => 'Partial transfer due to error',
        24 => 'Partial transfer due to vanished source files',
        25 => 'The --max-delete limit stopped deletions',
        30 => 'Timeout in data send/receive',
        35 => 'Timeout waiting for daemon connection',
    );
}

1;
