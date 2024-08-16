package Cpanel::EximStats::SpamCheck;

# cpanel - Cpanel/EximStats/SpamCheck.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::EximStats::SpamCheck - methods to query the eximstats DB for potential spammers

=head1 SYNOPSIS

    use Cpanel::EximStats::SpamCheck;

    Cpanel::EximStats::SpamCheck::run_spammer_check();

    my $end_t   = time();
    my $start_t = $end_t - 86400;

    my $unique_recipients_by_user = Cpanel::EximStats::SpamCheck::get_unique_recipient_count_by_user( $start_t, $end_t );
    my $unique_recipients_by_sender = Cpanel::EximStats::SpamCheck::get_unique_recipient_count_by_sender_for_user( $start_t, $end_t, "username" );

=cut

use Cpanel::AdminBin::Serializer ();    # PPI USE OK - LoadCpConf speed
use Cpanel::Config::LoadCpConf   ();
use Cpanel::Debug                ();
use Cpanel::EximStats::Constants ();

# Exposed for testing
our $_DB_DRIVER         = 'dbi:SQLite:';
our $_DEFAULT_THRESHOLD = 500;
our $_ENABLED_TWEAK     = "email_outbound_spam_detect_enable";
our $_ACTION_TWEAK      = "email_outbound_spam_detect_action";
our $_THRESHOLD_TWEAK   = "email_outbound_spam_detect_threshold";
our %_EMAIL_TO_USER;

# SPAM_TIME        - sets the span in seconds that we care about--how
#                    recently must the messages must have been sent to be
#                    considered spam
my $_SPAM_TIME = 60 * 60;

my $_BASE_WHERE_CLAUSE = q{
        WHERE
            sends.sender != '' AND
            sends.sender != 'root' AND
            sends.sender != 'nobody' AND
            sends.sender != 'cpanel' AND
            sends.auth != 'mailman' AND
            smtp.transport_is_remote=1 AND
            smtp.transport_method != '**bypassed**' AND
            SUBSTR(smtp.transport_method,1,9) != 'archiver_' AND
            SUBSTR(sends.sender,1,33) != '__cpanel__service__auth__icontact' AND
            sends.sendunixtime > ? AND
            sends.sendunixtime <= ?};

our $_SELECT_USER_COUNTS = qq{
    SELECT user, COUNT(recipient)
    FROM
    (
        SELECT
            DISTINCT
                sends.user as user,
                sends.sender as sender,
                smtp.email as recipient
        FROM sends INNER JOIN smtp on (sends.msgid=smtp.msgid)
        $_BASE_WHERE_CLAUSE
    )
    GROUP BY user
    HAVING user NOT NULL    -- Otherwise the query can give [ NULL, 0 ].
};

our $_SELECT_SENDER_COUNTS = qq{
    SELECT
        sends.sender,
        COUNT(DISTINCT(smtp.email)) AS msg_count
    FROM sends INNER JOIN smtp on (sends.msgid=smtp.msgid)
    $_BASE_WHERE_CLAUSE
    GROUP BY sends.sender
    HAVING msg_count > ?
    ORDER BY msg_count DESC
};

our $_SELECT_SENDER_COUNT_FOR_USER = qq{
    SELECT
        sends.sender,
        COUNT(DISTINCT(smtp.email))
        FROM sends INNER JOIN smtp on (sends.msgid=smtp.msgid)
        $_BASE_WHERE_CLAUSE AND
        sends.user = ?
    GROUP BY sends.sender
};

my ( %_DOMAIN_TO_USER, %_USER_THRESHOLDS );

=head2 run_spammer_check()

Queries the eximstats database for senders over a certain threshold (see
C<email_outbound_spam_detect_threshold> below), notifying and (potentially) blocking or
holding outgoing mail for those senders.

The behavior of this function is controlled by three tweak settings:

=over

=item C<email_outbound_spam_detect_enable>

A boolean value indicating whether or not spam detection is enabled. If this value is falsey
this function does nothing and returns true.

=item C<email_outbound_spam_detect_action>

A scalar value indicating what action to take in addition to the notification that is always
performed on each email account that is detected as a spammer.

One of:

=over

=item block

Email accounts detected as spammers will be blocked from sending outgoing mail

=item hold

Email accounts detected as spammers will have their outgoing mail held in the mail queue

=back

Any other value for C<email_outbound_spam_detect_action> will cause this function to
notify only.

=item C<email_outbound_spam_detect_threshold>

An integer value indicating the minimum number of unique recipients that an
email account must send mail to in order to be considered a spammer.

In addition to this tweak setting, each user may have a C<EMAIL_OUTBOUND_SPAM_DETECT_THRESHOLD>
value defined in their cpuserfile. If the user's C<EMAIL_OUTBOUND_SPAM_DETECT_THRESHOLD>
value is greater than the C<email_outbound_spam_detect_threshold> or is set to 0 or C<unlimited>,
then the user's value will be used instead of the tweak setting.

In the case where neither the C<email_outbound_spam_detect_threshold> tweak setting nor the
cpuserfile C<EMAIL_OUTBOUND_SPAM_DETECT_THRESHOLD> are defined a default threshold of 500
will be used.

=back

=over

=item Input

=over

None

=back

=item Output

=over

Returns 1 if the check completes successfully, dies otherwise.

=back

=back

=cut

sub run_spammer_check {

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return 1 if !$cpconf->{$_ENABLED_TWEAK};

    my $action = $cpconf->{$_ACTION_TWEAK} // q{noaction};

    my $spammer_threshold = $cpconf->{$_THRESHOLD_TWEAK} || $_DEFAULT_THRESHOLD;

    my $ts      = _time();
    my $results = _get_results( query => $_SELECT_SENDER_COUNTS, params => [ $ts - $_SPAM_TIME, $ts, $spammer_threshold ] );

    my $spammers_ref = _check_results_for_spammers( results => $results, default_threshold => $spammer_threshold ) if scalar @$results;
    undef $results;

    if ( $spammers_ref && @$spammers_ref ) {
        _take_action( $spammers_ref, $action );
        _notify( $spammers_ref, $action, $spammer_threshold );
    }

    return 1;
}

=head2 $unique_sender_recipient_count_per_user = get_unique_sender_recipient_count_per_user( start_time => $start_t, end_time => $end_t );

Gets the count of unique sender and recipient pairs for mail sent during the specified
time range, grouped by system user.

=over

=item Input

=over

=item C<start_time> C<SCALAR>

The beginning of the time range to query for in epoch seconds.

=item C<end_time> C<SCALAR>

The end of the time range to query for in epoch seconds.

=back

=item Output

=over

=item C<HASHREF>

Returns a C<HASHREF> where the keys are the usernames and the values are the count of unique
sender and recipient pairs for the mail sent.

=back

=back

=cut

sub get_unique_sender_recipient_count_per_user {

    my %args = @_;

    my @missing_parameters = grep { !length $args{$_} } qw(start_time end_time);

    if ( scalar @missing_parameters ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_parameters ] );
    }

    _validate_start_and_end_time(%args);

    return _get_unique_recipient_count( query => $_SELECT_USER_COUNTS, params => [ @args{qw(start_time end_time)} ] );
}

=head2 $unique_recipient_count_per_sender_for_user = get_unique_recipient_count_per_sender_for_user( start_time => $start_t, end_time => $end_t, user => $username )

Gets the number of unique email recipients that each email account owned by the specified user sent
mail to during the specified time range.

=over

=item Input

=over

=item C<start_time> C<SCALAR>

The beginning of the time range to query for in epoch seconds.

=item C<end_time> C<SCALAR>

The end of the time range to query for in epoch seconds.


=item C<user> C<SCALAR>

The username of the system account to query for.

=back

=item Output

=over

=item C<HASHREF>

Returns a C<HASHREF> where the keys are the email addresses and the values are the count of unique recipients
the email address sent mail to.

=back

=back

=cut

sub get_unique_recipient_count_per_sender_for_user {
    my %args = @_;

    my @missing_parameters = grep { !length $args{$_} } qw(start_time end_time user);

    if ( scalar @missing_parameters ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_parameters ] );
    }

    _validate_start_and_end_time(%args);

    return _get_unique_recipient_count( query => $_SELECT_SENDER_COUNT_FOR_USER, params => [ @args{qw(start_time end_time user)} ] );
}

sub _validate_start_and_end_time {

    my %args = @_;

    # Check for numeric values
    my @invalid_parameters = grep { $args{$_} !~ tr/0-9// } qw(start_time end_time);

    if ( scalar @invalid_parameters ) {
        require Cpanel::Exception;
        die Cpanel::Exception::create( 'InvalidParameter', "The [list_and_quoted,_1] [numerate,_2,parameter,parameters] must be [numerate,_2,a valid,valid] [asis,UNIX] epoch [numerate,_2,timestamp,timestamps].", [ \@invalid_parameters, scalar @invalid_parameters ] );
    }

    # Make sure start time is before end time
    if ( $args{start_time} >= $args{end_time} ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter must be less than the “[_2]” parameter.", [ 'start_time', 'end_time' ] );
    }

    my $now = _time();

    # Make sure end time is not in the future (start_time will have to be less than $now if end_time is)
    if ( $args{end_time} > $now ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The “[_1]” parameter cannot be greater than the current time (“[_2]”).", [ 'end_time', $now ] );
    }

    return;
}

# For testing
sub _time {
    return scalar time();
}

sub _get_unique_recipient_count {
    my %opts    = @_;
    my %ret_val = ();
    $ret_val{ $_->[0] } = $_->[1] for @{ _get_results(%opts) };
    return \%ret_val;
}

sub _connect {

    require DBD::SQLite;

    local $@;
    my $dbh = eval {
        DBI->connect(
            $_DB_DRIVER . $Cpanel::EximStats::Constants::EXIMSTATS_SQLITE_DB,
            undef, undef,
            {
                sqlite_open_flags                => DBD::SQLite::OPEN_READONLY(),
                sqlite_use_immediate_transaction => 0,
                RaiseError                       => 1,
                PrintWarn                        => 0,
            }
        );
    };

    if ( not $dbh or $DBI::errstr ) {
        my $err = $DBI::errstr // q{something went wrong};
        my $msg = qq{'$Cpanel::EximStats::Constants::EXIMSTATS_SQLITE_DB' - $err};
        Cpanel::Debug::log_warn($msg);
        die qq{$msg\n};
    }

    return $dbh;
}

sub _get_results {

    my %opts = @_;

    my $dbh = _connect();

    # Use of sqlite_see_if_its_a_number and prepare/execute syntax is to work around
    # DBD::SQLite always treating bind parameters as strings and quoting them when
    # doing comparisons to SQL func results
    # See: https://metacpan.org/pod/DBD::SQLite#Functions-And-Bind-Parameters
    $dbh->{sqlite_see_if_its_a_number} = 1;

    my $sth = $dbh->prepare( $opts{query} );
    $sth->execute( @{ $opts{params} } );

    my $results = $sth->fetchall_arrayref();

    $dbh->disconnect();

    return $results;
}

sub _get_system_user_for_sender {

    my ($sender) = @_;

    # Users can be assigned their own threshold for spamming, stored in their cpuserfile.
    # We keep a map of domain to user to avoid calling get_system_user for every sender
    # within the same domain.

    my $user;

    require Cpanel::Validate::EmailCpanel;
    my ( undef, $domain ) = Cpanel::Validate::EmailCpanel::get_name_and_domain($sender);

    # If we've already tried to find the system user for the domain, don't do the lookup again,
    # just assume it's whatever we already found
    if ( defined $domain && exists $_DOMAIN_TO_USER{$domain} ) {
        $user = $_DOMAIN_TO_USER{$domain};
    }
    else {
        require Cpanel::AcctUtils::Lookup;
        $user = eval { Cpanel::AcctUtils::Lookup::get_system_user($sender) } or undef;
        Cpanel::Debug::log_warn($@)       if $@;
        $_DOMAIN_TO_USER{$domain} = $user if $domain;
    }

    return $user;
}

sub _get_count_threshold_for_user {

    my ( $user, $default ) = @_;

    # We keep a map of user-level thresholds to avoid reloading the
    # cpuserfile for every email account the user has that's spamming.

    # If we haven't checked for a user-level spam threshold, we need to do so now
    if ( !exists $_USER_THRESHOLDS{$user} ) {

        require Cpanel::Config::LoadCpUserFile;
        my $cpuser = Cpanel::Config::LoadCpUserFile::load($user);

        my $cpuser_threshold = $cpuser->{EMAIL_OUTBOUND_SPAM_DETECT_THRESHOLD};

        if ( defined $cpuser_threshold ) {

            # The user's threshold has to either be 0, unlimited, or a number greater than $default, otherwise we just use $default
            if ( "$cpuser_threshold" eq "unlimited" ) {
                $_USER_THRESHOLDS{$user} = 0;
            }
            elsif ( $cpuser_threshold !~ tr/0-9//c && ( $cpuser_threshold == 0 || $cpuser_threshold > $default ) ) {
                $_USER_THRESHOLDS{$user} = $cpuser_threshold;
            }
            else {
                Cpanel::Debug::log_warn("The system detected an invalid outbound spam threshold for $user: $cpuser_threshold");
            }

        }

        if ( !defined $_USER_THRESHOLDS{$user} ) {
            $_USER_THRESHOLDS{$user} = $default;
        }

    }

    return $_USER_THRESHOLDS{$user};
}

sub _check_results_for_spammers {

    my %opts = @_;

    my ( $results, $default_threshold ) = @opts{qw(results default_threshold)};
    my @spammers = ();

    foreach my $line (@$results) {

        last if $line->[1] < $default_threshold;

        my $user = _get_system_user_for_sender( $line->[0] );
        next if !defined $user;

        my $count_threshold = _get_count_threshold_for_user( $user, $default_threshold );

        # A count threshold of 0 means unlimited
        if ( $count_threshold > 0 && $line->[1] >= $count_threshold ) {
            $_EMAIL_TO_USER{ $line->[0] } = $user;
            push @spammers, $line->[0];
        }

    }

    return \@spammers;
}

# dispatches to appropriate subroutine based on action to take; anticipating
# at least one more action to take
sub _take_action {
    my ( $spammers_ref, $action ) = @_;

    # do nothing if not set or explicitly set to 'noaction'
    return if not $action or $action eq q{noaction};

    # register new actions here
    my $actions = {
        'block' => \&_block_email_accounts,
        'hold'  => \&_hold_email_accounts,
    };

    # dispatch method call
    $actions->{$action}->($spammers_ref) if exists $actions->{$action};

    return;
}

sub _block_email_accounts {
    my ($spammers_ref) = @_;
    require Whostmgr::Accounts::Email;
    _do_callback_on_email_accounts( $spammers_ref, \&Whostmgr::Accounts::Email::suspend_mailuser_outgoing_email );
    return;
}

sub _hold_email_accounts {
    my ($spammers_ref) = @_;
    require Whostmgr::Accounts::Email;
    _do_callback_on_email_accounts( $spammers_ref, \&Whostmgr::Accounts::Email::hold_mailuser_outgoing_email );
    return;
}

sub _do_callback_on_email_accounts {

    my ( $spammers_ref, $callback ) = @_;

    foreach my $spammer (@$spammers_ref) {

        # block each email account
        local $@;
        my $user = $_EMAIL_TO_USER{$spammer};
        next if not defined $user;

        # do the actual suspension
        eval { $callback->( user => $user, email => ( $spammer =~ tr/A-Z/a-z/r ) ) };
        Cpanel::Debug::log_warn($@) if $@;
    }

    return;
}

sub _notify {

    my ( $spammers_ref, $action, $threshold ) = @_;

    return if !@$spammers_ref;

    my $spammers = join( ', ', @$spammers_ref );
    Cpanel::Debug::log_info("The system has detected an unusually large amount of outbound email. The following sender(s) may be sending spam: $spammers");
    require Cpanel::iContact::Class::Mail::SpammersDetected;
    require Cpanel::Notify;
    Cpanel::Notify::notification_class(
        constructor_args => [ origin => 'eximstats_spam_check', spam_count => $threshold, spammers => $spammers_ref, action => $action ],
        map { $_ => q{Mail::SpammersDetected} } qw(class application),
    );
    return;
}

1;
