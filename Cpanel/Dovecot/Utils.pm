package Cpanel::Dovecot::Utils;

# cpanel - Cpanel/Dovecot/Utils.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Dovecot::Utils - Dovecot manipulation logic

=head1 SYNOPSIS

    my $doveadm_bin = Cpanel::Dovecot::Utils::doveadm_bin();
    my $dsync_bin   = Cpanel::Dovecot::Utils::dsync_bin();

    Cpanel::Dovecot::Utils::flush_auth_caches('foo@bar.com');
    Cpanel::Dovecot::Utils::flush_auth_caches('foo@bar.com', 'hal@bar.com');
    Cpanel::Dovecot::Utils::flush_all_auth_caches();

    my $mbstats_hr = Cpanel::Dovecot::Utils::get_mailbox_status('foo@bar.com');

    Cpanel::Dovecot::Utils::recalc_quota( account => 'foo@bar.com' );

    Cpanel::Dovecot::Utils::expunge_mailbox_messages(
        account => 'foo@bar.com',
        mailbox => 'INBOX.haha',    #it’s a wildcard!
        query => 'ALL',
    );

    Cpanel::Dovecot::Utils::expunge_messages_for_mailbox_guid(
        account => 'foo@bar.com',
        mailbox_guid => '123abc6786ffed',   #etc.
        query => 'ALL',
    );

    Cpanel::Dovecot::Utils::purge('foo@bar.com');
    Cpanel::Dovecot::Utils::expunge('foo@bar.com', 'INBOX.mailboxname', $days);
    Cpanel::Dovecot::Utils::kick('foo@bar.com');

    Cpanel::Dovecot::Utils::force_resync('foo@bar.com');

=head1 DESCRIPTION

This is a kind of “kitchen sink” module for Dovecot commands.

Note that “ACCOUNT” arguments as documented here can be either
system usernames (for “default” email accounts) or email account names
(e.g., C<mailuser@example.com>).

=head1 IMPLEMENTATION NOTE

Most of what\’s in here calls the C<doveadm> binary. It is possible
to call Dovecot directly via the protocol described
L<here|http://wiki2.dovecot.org/Design/DoveadmProtocol>; however, in
testing that hasn’t seemed to offer much benefit over just calling the
binary—it was actually slower, in fact.

It may be worth revisiting this at a later point.

=head1 FUNCTIONS

=cut

use cPstrict;

use Cpanel::CPAN::IO::Callback::Write ();
use Cpanel::FindBin                   ();
use Cpanel::Exception                 ();
use Cpanel::SafeRun::Object           ();
use Cpanel::Dovecot                   ();
use Cpanel::Dovecot::Doveadm          ();
use Cpanel::Services::Enabled         ();
use Cpanel::JSON                      ();

my $_doveadm_bin;
my $_dsync_bin;

my $dovecotadm_socket_cache;
my $dovecotadm_cache_pid;

=head2 doveadm_bin() dsync_bin()

These return the filesystem path of the C<doveadm> and C<dsync>
binaries, respectively.

=cut

# We should be using the server protocol as its much much faster
# http://wiki2.dovecot.org/Design/DoveadmProtocol
sub doveadm_bin {
    return ( $_doveadm_bin ||= _findbin_or_die('doveadm') );
}

sub dsync_bin {
    return ( $_dsync_bin ||= _findbin_or_die('dsync') );
}

#----------------------------------------------------------------------

=head2 flush_auth_caches( ACCOUNT, ACCOUNT, ... ) flush_all_auth_caches()

Flush Dovecot’s auth cache for a given list of accounts, or all of them.
See C<doveadm help auth> for more information.

=cut

sub flush_auth_caches {
    my (@accounts) = @_;

    die "Need at least one account!" if !@accounts;

    return _flush_auth_cache(@accounts);
}

sub flush_all_auth_caches {
    return _flush_auth_cache();
}

sub _flush_auth_cache {
    my (@accounts) = @_;

    my $run = Cpanel::SafeRun::Object->new(
        program => doveadm_bin(),
        args    => [ 'auth', 'cache', 'flush', '--', @accounts ],
    );

    # Do not error if dovecot is offline since there will be no cache
    return _die_if_not_error_except( $run, [$Cpanel::Dovecot::DOVEADM_EX_TEMPFAIL] );
}

#----------------------------------------------------------------------

=head2 get_mailbox_status( ACCOUNT, TIMEOUT )

Returns a hashref whose keys are mailbox names (e.g., C<INBOX>, C<INBOX.Sent>)
and whose values are hashrefs with the C<messages>, C<vsize>, and C<guid>
values as C<doveadm mailbox status> reports.

Function uses C<Cpanel::SafeRun::Object> and can emit any exception thrown by
C<new_or_die()> of that object. If provided, the optional C<TIMEOUT> parameter
is passed to C<Cpanel::SafeRun::Object> to replace that object's default value.

Example:

    {
        'foo@bar.com' => {
            messages => 20,
            vsize => 259,   #NB: KiB
            guid => '0123dd6abffe789655',
        },
        #...
    }

=cut

sub get_mailbox_status {
    my ( $account, $timeout ) = @_;

    my %mailboxes;

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => doveadm_bin(),
        args    => [
            -f => 'pager',
            'mailbox', 'status',
            '-u' => $account,
            'messages vsize guid',

            #doveadm apparently doesn’t have a way to specify a
            #literal asterisk. :-/
            'INBOX', 'INBOX.*',
        ],

        # if optional timeout parameter isn't provided, let SafeRun use its default:
        ( defined($timeout) ? ( timeout => $timeout ) : () ),
    );

    foreach my $mailbox_data ( split( m{\n*\f+\n*}, $run->stdout() ) ) {
        my ( $mailbox_name, @attrs ) = split m<\n>, $mailbox_data;

        $mailboxes{$mailbox_name} = { map { split( m<\s*:\s*>, $_, 2 ) } @attrs };
    }

    return \%mailboxes;
}

=head2 recalc_quota( ACCOUNT )

Recompute the account’s quota. (cf. C<doveadm quota recalc>)

=cut

sub recalc_quota {
    my (%opts) = @_;

    foreach my $required (qw(account)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }
    return _run_doveadm_until_success(
        'maximum_attempts' => 5,
        'args'             => [ 'quota', 'recalc', '-u', $opts{'account'} ],
    );
}

#----------------------------------------------------------------------

=head2 expunge_messages_for_mailbox_guid( ... )

Delete messages in a mailbox.

Inputs are a list of key/value pairs:

=over

=item * C<account> (required) - The account to operate on, e.g., C<bob>, C<mail@bob.com>, etc.

=item * C<query> (required) - The dovecot query to execute (see doveadm-search-query: L<http://wiki2.dovecot.org/Tools/Doveadm/SearchQuery>)

=item *  C<mailbox_guid> (required) - The GUID of the mailbox to operate on. Mailbox GUIDs are given in the
return of C<get_mailbox_status_list()>.

=back

C<query> is required in order to prevent accidental removal of all messages in the mailbox.

=cut

sub expunge_messages_for_mailbox_guid {
    my (%opts) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'mailbox_guid' ] ) if !$opts{'mailbox_guid'};

    return _expunge_mailbox_messages(
        %opts,
        mailbox_specification => [ 'mailbox-guid' => $opts{'mailbox_guid'} ],
    );
}

=head2 expunge_mailbox_messages( ... )

The same function as C<expunge_messages_for_mailbox_guid()>,
but instead of C<mailbox_guid>, it accepts:

=over

=item * C<mailbox> - A pattern to match for mailboxes whose mail to delete.
This pattern treats C<*> and C<?> as their familiar wildcard values.

=back

=cut

sub expunge_mailbox_messages {
    my (%opts) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'mailbox' ] ) if !$opts{'mailbox'};

    return _expunge_mailbox_messages(
        %opts,
        mailbox_specification => [ mailbox => $opts{'mailbox'} ],
    );
}

sub _expunge_mailbox_messages {
    my (%opts) = @_;

    foreach my $required (qw(account query)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }

    require Cpanel::StringFunc::SplitBreak;

    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => doveadm_bin(),
        args    => [
            ( $opts{'verbose'} ? ('-v') : () ),
            'expunge',

            '-u' => $opts{'account'},

            '--',

            @{ $opts{'mailbox_specification'} },

            Cpanel::StringFunc::SplitBreak::safesplit( q< >, $opts{'query'} ),
        ],
    );

    my %ret;
    if ( $run->stderr() ) { $ret{'errors'}   = $run->stderr(); }
    if ( $run->stdout() ) { $ret{'messages'} = $run->stdout(); }
    return \%ret;
}

#----------------------------------------------------------------------

=head2 purge( ACCOUNT )

Remove all of the account’s 0-refcount messages.
(cf. L<doveadm-purge(1)>)

(NB: To delete all of an account’s messages, call
C<expunge_mailbox_messages()> with a C<mailbox> of C<*>
and C<query> of C<ALL>.)

=cut

sub purge {
    my ($account) = @_;
    return _run_doveadm_until_success(
        'maximum_attempts' => 5,
        'args'             => [ 'purge', '-u', $account ],
    );
}

=head2 expunge( ACCOUNT, MAILBOX, DAYS_TTL )

Remove all of the account’s mail in a given mailbox that is over DAYS_TTL
days old.

=cut

sub expunge {
    my ( $account, $mailbox, $days_ttl ) = @_;
    return _run_doveadm_until_success(
        'maximum_attempts' => 5,
        'args'             => [ 'expunge', '-u', $account, 'mailbox', $mailbox, 'savedbefore', $days_ttl . 'd' ],
    );
}

=head2 kick( @PATTERNS )

Terminate a current Dovecot connections that the referenced @PATTERNS
may match.

Each @PATTERNS is normally a cPanel user’s name (e.g., C<bob>) or email
account name (e.g., C<bob@bobs-stuff.com>), but it may also include
wildcards and any other syntactical variants described in L<doveadm-kick(1)>.

=cut

sub kick (@account_names) {

    # At some point we should implement kicking exim as well
    # http://www.gossamer-threads.com/lists/exim/users/97129
    # https://github.com/Exim/exim/wiki/BlockCracking

    _get_dovecotadm_socket();

    require Cpanel::Try;

    # Doing these in series appears to be performant even with
    # hundreds of account names.
    for my $acctname (@account_names) {
        Cpanel::Try::try(
            sub {
                () = $dovecotadm_socket_cache->do_debug( q<>, 'kick', $acctname );
            },
            'Cpanel::Exception::Doveadm::Error' => sub {
                my $err    = $@;
                my $status = $err->get('status');

                # Like ENOENT in response to unlink(), NOTFOUND isn’t
                # really an error; it’s just Dovecot telling us that
                # no logged-in users matched $acctname.
                #
                # (cf. Dovecot source code, src/doveadm/doveadm-kick.c)
                #
                # NB: Only “NOTFOUND” is observed to happen. It’s
                # assumed--but not confirmed--that doveadm indicates that
                # error via the string “TEMPFAIL”.
                #
                if ( $status ne 'NOTFOUND' && $status ne 'TEMPFAIL' ) {
                    die $err;
                }
            },
        );
    }

    return 1;
}

=head2 kick_all_sessions_for_cpuser( USERNAME )

Like C<kick()>, but terminates all sessions for any accounts
that the indicated cPanel user owns.

=cut

sub kick_all_sessions_for_cpuser ($username) {
    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    my $added_domains_ar = $cpuser_ref->{'DOMAINS'};

    my @to_kick = (
        $username,
        ( map { "*\@$_" } $cpuser_ref->{'DOMAIN'}, @$added_domains_ar ),
    );

    for my $item (@to_kick) {
        if ( !eval { kick($item); 1 } ) {
            warn Cpanel::Exception::get_string($@) . "\n";
        }
    }

    return;
}

=head2 force_resync( ACCOUNT )

Repair the account’s C<INBOX>.

=cut

sub force_resync {
    my ($account) = @_;
    return _run_doveadm_until_success(
        'maximum_attempts' => 5,
        args               => [ 'force-resync', '-u', $account, 'INBOX' ]
    );
}

=head2 fts_rescan_mailbox( ACCOUNT )

function description

=head3 Arguments

=over 4

=item ACCOUNT    - SCALAR - The mailbox to rescan for FTS indexing

=back

=head3 Returns

Nothing.

=head3 Exceptions

Anything that Cpanel::Dovecot::Doveadm can throw.

=cut

sub fts_rescan_mailbox {
    my (%opts) = @_;

    foreach my $required (qw(account)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }

    if ( !Cpanel::Services::Enabled::is_enabled('cpanel-dovecot-solr') ) {
        die Cpanel::Exception::create( 'Services::Disabled', [ 'service' => 'cpanel-dovecot-solr' ] );
    }

    _get_dovecotadm_socket();

    require Cpanel::Try;
    Cpanel::Try::try(
        sub {
            () = $dovecotadm_socket_cache->do(
                $opts{account},
                'fts rescan',
            );
        },
        'Cpanel::Exception::Doveadm::Error' => sub {
            my $err            = $@;
            my $doveadm_status = $err->get('status');

            if ( $doveadm_status eq 'NOUSER' ) {
                die Cpanel::Exception::create( 'UserNotFound', [ name => $opts{'account'} ] );
            }
            elsif ( $doveadm_status eq 'NOTFOUND' || $doveadm_status eq q<> ) {
                die Cpanel::Exception::create( 'Plugin::NotInstalled', [ plugin => 'Dovecot FTS Solr' ] );
            }

            local $@ = $err;
            die;
        },
    );

    return;
}

=head2 create_and_subscribe_mailbox

Creates and subscribes to a mailbox for a specific account

=over 2

=item Input

=over 3

=item account C<SCALAR>

The email account or system user to create the mailbox for

=item mailbox C<SCALAR>

The name of the mailbox to create

=back

=item Output

=over 3

Dies if either input parameter is missing or there is an error creating or subscribing to the mailbox.

No output otherwise.

=back

=back

=cut

sub create_and_subscribe_mailbox {

    my (%opts) = @_;

    my @missing = grep { !length $opts{$_} } qw(account mailbox);
    die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing ] ) if @missing;

    my $create = Cpanel::SafeRun::Object->new(
        program => doveadm_bin(),
        args    => [ 'mailbox', 'create', '-s', '-u', $opts{account}, $opts{mailbox} ],
    );

    # doveadm returns 65 for both the mailbox already existing and a failure to create
    # it, so look for the already exists output. It will subscribe the mailbox even if
    # it already exists.
    if ( $create->stderr() && index( $create->stderr(), "already exists" ) == -1 ) {
        _warn_saferun_errors($create);
        $create->die_if_error();
    }

    return;
}

# Called from tests, but could be useful elsewhere.

=head2 search( ... )

Search for messages in a specified account's mailboxes.

Inputs are a list of key/value pairs:

=over

=item * C<account> (required) - The account to operate on, e.g., C<bob>, C<mail@bob.com>, etc.

=item * C<query> (required) - The dovecot query to execute (see doveadm-search-query: L<http://wiki2.dovecot.org/Tools/Doveadm/SearchQuery>)

=back

Returns an arrayref of hashrefs with keys C<mailbox-guid> and C<uid> representing the search output.

=cut

sub search {
    my (%opts) = @_;

    foreach my $required (qw(account query)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }

    my @query_terms;

    if ( ref $opts{'query'} eq 'ARRAY' ) {
        @query_terms = @{ $opts{'query'} };
    }
    elsif ( ref $opts{'query'} eq '' ) {
        @query_terms = grep { $_ } split ' ', $opts{'query'};
    }
    else {
        die Cpanel::Exception::create_raw( 'InvalidParameter', '“query” must be a string or an arrayref' );
    }

    # TODO: replace new_or_die() with new() + proper exception generation
    # e.g., error code 67 should throw Cpanel::Exception::UserNotFound?
    #       error code 75 + stderr contains 'Unknown print formatter' should throw Cpanel::Exception::Unsupported?
    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => doveadm_bin(),
        args    => [
            '-f' => 'json',
            'search',
            '-u' => $opts{'account'},
            @query_terms,
        ],
    );

    return Cpanel::JSON::Load( $run->stdout() );
}

=head2 fetch( ... )

Fetches specified fields of messages in a specified account's mailboxes.

Inputs are a list of key/value pairs:

=over

=item * C<account> (required) - The account to operate on, e.g., C<bob>, C<mail@bob.com>, etc.

=item * C<fields> (required) - A space-delimited string of fields specifying to C<doveadm fetch> what data to return.

=item * C<query> (required) - The dovecot query to execute (see doveadm-search-query: L<http://wiki2.dovecot.org/Tools/Doveadm/SearchQuery>)

=back

Returns an arrayref of hashrefs representing the output of C<doveadm fetch>.

=cut

sub fetch {
    my (%opts) = @_;

    foreach my $required (qw(account fields query)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }

    my @query_terms;
    if ( ref $opts{'query'} eq 'ARRAY' ) {
        @query_terms = @{ $opts{'query'} };
    }
    elsif ( ref $opts{'query'} eq '' ) {
        @query_terms = grep { $_ } split ' ', $opts{'query'};
    }
    else {
        die Cpanel::Exception::create_raw( 'InvalidParameter', '“query” must be a string or an arrayref' );
    }

    my ( $fields, @fields );
    if ( ref $opts{'fields'} eq 'ARRAY' ) {
        @fields = @{ $opts{'fields'} };
        $fields = join ' ', @fields;
    }
    elsif ( ref $opts{'fields'} eq '' ) {
        $fields = $opts{'fields'};
        @fields = grep { $_ } split ' ', $opts{'fields'};
    }
    else {
        die Cpanel::Exception::create_raw( 'InvalidParameter', '“fields” must be a string or an arrayref' );
    }

    # TODO: replace new_or_die() with new() + proper exception generation
    my $run = Cpanel::SafeRun::Object->new_or_die(
        program => doveadm_bin(),
        args    => [
            '-f' => 'json',
            'fetch',
            '-u' => $opts{'account'},
            $fields,
            @query_terms,
        ],
    );

    return Cpanel::JSON::Load( $run->stdout() );
}

#----------------------------------------------------------------------

our @doveadm_output;

sub _create_doveadm_write_callback {
    return Cpanel::CPAN::IO::Callback::Write->new(
        sub { push @doveadm_output, shift },
    );
}

#called in tests
sub _run_doveadm_until_success {
    my (%opts) = @_;

    foreach my $required (qw(args maximum_attempts)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }
    if ( !$opts{'maximum_attempts'} || $opts{'maximum_attempts'} < 1 || $opts{'maximum_attempts'} > 100 ) {
        die Cpanel::Exception::create( 'InvalidParameter', "The value for “[_1]” must be a whole number between [numf,_2] and [numf,_3].", 'maximum_attempts', 1, 100 );
    }

    foreach my $attempt ( 1 .. $opts{'maximum_attempts'} ) {
        @doveadm_output = join( ' ', doveadm_bin(), @{ $opts{args} } ) . "\n";
        my $run = Cpanel::SafeRun::Object->new(
            program => doveadm_bin(),
            args    => $opts{'args'},
            stdout  => _create_doveadm_write_callback(),
        );

        return 1 unless $run->CHILD_ERROR();

        my $error_code = $run->error_code();
        if ( $error_code && $error_code == $Cpanel::Dovecot::DOVEADM_EX_NOTFOUND ) {
            _warn_saferun_errors($run);
            return 0;
        }
        elsif ( $error_code && $error_code == $Cpanel::Dovecot::DOVEADM_EX_TEMPFAIL ) {
            if ( $attempt == $opts{'maximum_attempts'} ) {
                _warn_saferun_errors($run);
                return 0;
            }
            _wait_for_dovecot_to_come_back_up();
            next;
        }
        else {
            _warn_saferun_errors($run);
        }
    }

    return 0;
}

sub _wait_for_dovecot_to_come_back_up {
    return sleep(5);
}

#----------------------------------------------------------------------

sub _findbin_or_die {
    my ($bin) = @_;

    my $path = Cpanel::FindBin::findbin($bin);
    if ( !$path ) {
        die Cpanel::Exception->create( 'The system failed to find a program named “[_1]”.', [$bin] );
    }

    return $path;
}

sub _die_if_not_error_except {
    my ( $run, $allowed_errors ) = @_;
    if ( $run->CHILD_ERROR() ) {
        my $error_code = $run->error_code();
        if ( !$error_code || !( grep { $error_code == $_ } @{$allowed_errors} ) ) {
            _warn_saferun_errors($run);
            $run->die_if_error();
        }
    }
    return 1;
}

sub _warn_saferun_errors {
    my ($run) = @_;
    warn $run->autopsy() . ": " . $run->stderr();
    return;
}

sub _get_dovecotadm_socket {
    die "This must run as root!\n" if $>;

    if ( $dovecotadm_socket_cache && $dovecotadm_cache_pid && $dovecotadm_cache_pid == $$ ) {
        return $dovecotadm_socket_cache;
    }

    $dovecotadm_socket_cache = Cpanel::Dovecot::Doveadm->new();
    $dovecotadm_cache_pid    = $$;

    return $dovecotadm_socket_cache;
}

1;
