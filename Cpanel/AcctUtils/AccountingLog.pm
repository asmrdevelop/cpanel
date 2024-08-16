package Cpanel::AcctUtils::AccountingLog;

# cpanel - Cpanel/AcctUtils/AccountingLog.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug       ();
use Cpanel::ConfigFiles ();
use Cpanel::SafeFile    ();

=head1 NAME

Cpanel::AcctUtils::AccountingLog

=head1 SYNOPSIS

    Cpanel::AcctUtils::AccountingLog::append_entry('CREATE', ['domain.example.com', 'username'])

=head1 DESCRIPTION

A very no frills implementation of a helper method for appending entries to the accounting log.

=head1 SUBROUTINES

=over

=item append_entry($action, $log_data_ref)

Append an entry for a given action with the provided log_data_ref params.

=over

=item B<action>

A string that reflects the accounting activity being logged.

=item B<log_data_ref>

An array reference of strings that will be logged as a colon delimited list in the accounting log.

=back

=back

=cut

sub append_entry {
    my ( $action, $log_data_ref ) = @_;

    die 'action is required' if !$action;

    if ( !defined $log_data_ref || !ref $log_data_ref ) {
        die 'log data array ref is required';
    }

    my $acctlog;
    my $lock = Cpanel::SafeFile::safeopen( $acctlog, '>>', $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );

    if ( !$lock ) {
        Cpanel::Debug::log_warn("Could not write to $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE: $!");
        return 0;
    }

    _chmod( 0600, $Cpanel::ConfigFiles::ACCOUNTING_LOG_FILE );

    my $env_remote_user = $ENV{'REMOTE_USER'} // 'unknown';
    my $env_user        = $ENV{'USER'}        // 'unknown';

    print $acctlog join( q{:}, ( _localtime_now(), $action, $env_remote_user, $env_user, map { _sanitize_entry($_) } @{$log_data_ref} ) ) . "\n";

    Cpanel::SafeFile::safeclose( $acctlog, $lock );

    return 1;
}

sub _sanitize_entry {
    my $entry = shift;
    $entry //= '';
    $entry =~ s{:}{\\:}g;
    return $entry;
}

# For testing
sub _chmod {
    return chmod @_;
}

# For testing
sub _localtime_now {
    return scalar localtime( time() );
}

1;
