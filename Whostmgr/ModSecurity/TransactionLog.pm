
# cpanel - Whostmgr/ModSecurity/TransactionLog.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::ModSecurity::TransactionLog;

use strict;
use Cpanel::Time          ();
use Whostmgr::ModSecurity ();
use Fcntl                 ();

=head1 NAME

Whostmgr::ModSecurity::TransactionLog

=head1 SUBROUTINES

=head2 log()

Produce an entry in the ModSecurity Tools transaction log.

=head3 Arguments

'operation': (REQUIRED) The name of the operation that was performed -- e.g., disable_rule.
The convention should be to use whatever the name of the API function is / would be, but
with the 'modsec_' prefix stripped off.

'arguments': (REQUIRED) A hash ref containing the arguments supplied to the operation. If
an argument is overly long or complex, its value will be omitted from the log.

=head3 Example

    sub myfunction {
        my %args = @_;

        ... # do some work

        Whostmgr::ModSecurity::TransactionLog::log( operation => 'myfunction', arguments => \%args );
        return 1;
    }

=cut

sub log {
    my %info = @_;

    my $timestamp = Cpanel::Time::time2datetime(time);
    my $client =
        $ENV{REMOTE_ADDR} ? "$ENV{REMOTE_ADDR} (WHM: $ENV{REMOTE_USER})"
      : $ENV{SSH_CLIENT}  ? "$ENV{SSH_CLIENT} (ssh)"
      :                     'unknown';
    my $operation = $info{operation} || 'unknown';
    my $arguments = _serialize_arguments( $info{arguments} );

    # 1. No locking because that could block, and speed is more important than the
    #    integrity of this log data.
    # 2. Silent failure because logging problems should not disrupt functionality.
    my $log_fh;
    sysopen $log_fh, Whostmgr::ModSecurity::abs_modsec_transaction_log(), Fcntl::O_WRONLY() | Fcntl::O_CREAT() | Fcntl::O_APPEND(), 0600 or return;
    print {$log_fh} <<END;
timestamp: $timestamp
client:    $client
operation: $operation
arguments: $arguments
----
END
    close $log_fh;

    return 1;
}

sub _serialize_arguments {
    my ($arguments) = @_;
    if ( 'HASH' eq ref $arguments ) {
        return join ';', map {
            my ( $key, $value ) = map { _sanitize($_) } $_, $arguments->{$_};
            "$key=$value";
        } sort keys %$arguments;
    }
    elsif ( 'ARRAY' eq ref $arguments ) {
        return join ',', map { _sanitize($_) } @$arguments;
    }
    return 'unknown';
}

sub _sanitize {
    my ($thing) = @_;
    return '(omitted)' if length($thing) > 512 or $thing =~ /[;,=\n]/;
    return $thing;
}

1;
