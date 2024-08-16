package Cpanel::Async::MailSync;

# cpanel - Cpanel/Async/MailSync.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use experimental 'isa';

=encoding utf-8

=head1 NAME

Cpanel::Async::MailSync

=head1 SYNOPSIS

    my $account_promise_hr = Cpanel::Async::MailSync::sync_to_local(
        username => 'bobby',
        remote_host => 'the.remote.hostname',
        remote_api_token => 'THEAPITOKEN',
        remote_username => 'root',
    );

=head1 DESCRIPTION

This module implements a full mail sync for a cPanel account, including
the system account and all email subaccounts.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::Exec                  ();
use Cpanel::Config::LoadCpUserFile       ();
use Cpanel::Dovecot                      ();
use Cpanel::Dsync::CpsrvdClient          ();
use Cpanel::Email::Accounts              ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::PromiseUtils                 ();
use Cpanel::PwCache                      ();

use constant {
    _MAX_CONCURRENT_DSYNCS => 4,
    _MAX_DSYNC_RETRIES     => 10,
    _MAILSYNC_TIMEOUT      => 3600 * 24,
};

# overridden in tests
our $_DELAY_BETWEEN_RETRIES;

BEGIN {
    $_DELAY_BETWEEN_RETRIES = 10;
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 $account_promise_hr = sync_to_local( %OPTS )

Wraps the equivalent function in L<Cpanel::Dsync::CpsrvdClient>.

%OPTS are:

=over

=item * C<application> - As given to L<Cpanel::Dsync::CpsrvdClient>.

=item * C<username> - The cPanel username whose mail to sync.

=item * C<remote_host> - The remote hostname.

=item * C<remote_api_token> - A WHM API token.

=item * C<remote_username> - The name of the user that matches the
C<remote_api_token>.

=back

This returns a hashref of account name (which will include the system
account’s username as well as the email accounts’ names) to a promise
that resolves/rejects when the sync finishes.

Note that this will only synchronize mailboxes that exist locally;
if the remote has mailboxes (i.e., email accounts) that don’t exist
locally, then such mailboxes won’t be part of the sync operation.

=cut

sub sync_to_local (%opts) {
    return _sync( 'sync_to_local', %opts );
}

#----------------------------------------------------------------------

=head2 $account_promise_hr = sync_to_remote( %OPTS )

Wraps the equivalent function in L<Cpanel::Dsync::CpsrvdClient>.

Inputs & outputs match C<sync_to_local()> above.

=cut

sub sync_to_remote (%opts) {
    return _sync( 'sync_to_remote', %opts );
}

#----------------------------------------------------------------------

sub _sync ( $action, %opts ) {
    my $cpuser      = Cpanel::Config::LoadCpUserFile::load_or_die( $opts{'username'} );
    my $main_domain = $cpuser->{'DOMAIN'};

    my ( $popaccts_ref, $_manage_err ) = do {
        my $privs = Cpanel::AccessIds::ReducedPrivileges->new( $opts{'username'} );

        local $Cpanel::homedir = Cpanel::PwCache::gethomedir();

        Cpanel::Email::Accounts::manage_email_accounts_db(
            'event' => 'fetch',
        );
    };
    die $_manage_err if !$popaccts_ref;

    my $execer = Cpanel::Async::Exec->new(
        process_limit => _MAX_CONCURRENT_DSYNCS,
    );

    my @common_dsync_args = (
        execer => $execer,
        %opts{'application'},
        peer           => $opts{'remote_host'},
        authn_username => $opts{'remote_username'},
        api_token      => $opts{'remote_api_token'},
        timeout        => _MAILSYNC_TIMEOUT,
    );

    my %user_promise;

    my $sync_cr = Cpanel::Dsync::CpsrvdClient->can($action) or do {
        require Carp;
        Carp::confess("bad action: $action");
    };

    $user_promise{ $opts{'username'} } = _retried_sync(
        $opts{'username'},
        $sync_cr,
        @common_dsync_args,
        account_name        => $opts{'username'},
        remote_account_name => "_mainaccount\@$main_domain",
    );

    # Sorts are just so we do things in a predictable order.
    for my $domain ( sort keys %$popaccts_ref ) {
        for my $login ( sort keys %{ $popaccts_ref->{$domain}{'accounts'} } ) {
            my $account_name = "$login\@$domain";

            $user_promise{$account_name} = _retried_sync(
                $account_name,
                $sync_cr,
                @common_dsync_args,
                account_name        => $account_name,
                remote_account_name => $account_name,
            );
        }
    }

    return \%user_promise;
}

sub _retried_sync ( $account_name, $sync_cr, @dsync_args ) {    ## no critic qw(ManyArgs) - mis-parse
    return Cpanel::PromiseUtils::retry(
        sub ($tries) {
            my $delay = $tries && Cpanel::PromiseUtils::delay($_DELAY_BETWEEN_RETRIES);
            $delay ||= Promise::XS::resolved();

            return $delay->then(
                sub {
                    $sync_cr->(@dsync_args);
                }
            );
        },
        _MAX_DSYNC_RETRIES,
        sub ($err) { _should_retry( $err, $account_name ) },
    );
}

sub _should_retry ( $err, $acctname ) {
    my $should_yn;

    if ( $err isa 'Cpanel::Exception::ProcessFailed::Error' ) {
        $should_yn = 1;

        my $out = join "\n", grep { length } map { $err->get($_) } qw(stdout stderr);
        warn $out if length $out;
    }

    $should_yn &&= $err->get('error_code') == $Cpanel::Dovecot::DOVEADM_EX_TEMPFAIL;

    # Use %s for the delay number because Perl’s stringification better
    # suits testing, where we delay for a very short time.
    warn sprintf( "%s: temporary failure; retrying after %s seconds …\n", $acctname, $_DELAY_BETWEEN_RETRIES ) if $should_yn;

    return $should_yn;
}

1;
