package Cpanel::API::SpamAssassin;

# cpanel - Cpanel/API/SpamAssassin.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel                       ();
use Cpanel::SpamAssassin::Config ();
use Cpanel::Exception            ();
use Cpanel::Validate::Number     ();

our %API = (
    _needs_feature    => 'spamassassin',
    _worker_node_type => 'Mail',
);

=encoding utf-8

=head1 NAME

Cpanel::API::SpamAssassin - API functions related to SpamAssassin

=head1 SYNOPSIS

    use Cpanel::API::SpamAssassin;

    uapi SpamAssassin get_user_preferences   --user=MYUSER
    uapi SpamAssassin update_user_preference --user=MYUSER preference=whitelist_from values=['whitelist_from1','whitelist_from2']

=head1 DESCRIPTION

API functions related to SpamAssassin

=cut

=head2 get_user_preferences

Get the SpamAssassin user preferences for the current user

=over 2

=item Output

=over 3

=item C<HASHREF>

    returns a hashref of the key value pairs stored in the ~/.spamassassin/user_prefs file
    {
        required_score => ['8'],
        whitelist_from => ['one','two','three'],
        blacklist_from => ['one','two','three'],
    }

=back

=back

=cut

sub get_user_preferences {
    my ( $args, $result ) = @_;

    my $config = Cpanel::SpamAssassin::Config::get_user_preferences();
    $result->data($config);

    return 1;
}

=head2 update_user_preference

Update a specific user preference for the SpamAssassin user_prefs file

=over 2

=item Input

=over 3

=item C<SCALAR>

    preference - key name associated with the spamassassin user preference to update

=item C<SCALAR>

    value - the values to update. will handle multiple values (whitelist_from, blacklist_from)

=back

=item Output

=over 3

=item C<HASHREF>

    returns a hashref of the key value pairs stored in the ~/.spamassassin/user_prefs file with the updated values provided
    {
        required_score => ['8'],
        whitelist_from => ['one','two','three'],
        blacklist_from => ['one','two','three'],
    }

=back

=back

=cut

sub update_user_preference {
    my ( $args, $result ) = @_;

    my $preference = $args->get_length_required("preference");
    my @values     = $args->get_multiple('value');

    # trimming values
    s/^\s+|\s+$//g for @values;

    # These need further validation
    if ( $preference eq "score" ) {

        my $scores     = _get_sa_scores();
        my @score_keys = sort grep { index( $_, '__' ) != 0 } keys %$scores;
        my @clean_values;

        foreach my $value (@values) {

            my ( $score_key, $score_value ) = split( /\s+/, $value );

            if ( !$score_key ) {
                die Cpanel::Exception::create( "InvalidParameter", '“[_1]” is not a valid “[_2]” value. You must provide a [asis,SYMBOLIC_TEST_NAME].', [ $value, $preference ] );
            }

            unless ( grep { $_ eq $score_key } @score_keys ) {
                die Cpanel::Exception::create( "InvalidParameter", '“[_1]” is not a valid [asis,SYMBOLIC_TEST_NAME] for the “[_2]” value.', [ $score_key, $preference ] );
            }

            try {
                Cpanel::Validate::Number::rational_number($score_value);
            }
            catch {
                die Cpanel::Exception::create( 'InvalidParameter', 'The value for “[_1]” ([_2]) is invalid. ([_3])', [ $score_key, $score_value, $_->to_locale_string_no_id() ] );
            };

            #Reduce, e.g., “7.0” to “7”
            $score_value += 0;

            push @clean_values, $score_key . " " . $score_value;
        }

        @values = @clean_values;
    }

    my $config = Cpanel::SpamAssassin::Config::update_user_preference( $preference, \@values );
    $result->data($config);

    return 1;
}

=head2 get_symbolic_test_names

Gather the list of rule keys from SpamAssassin

=over 2

=item Output

=over 3

=item C<ARRAYREF>

    returns an array of hashrefs
    -
      key: HK_LOTTO
      rule_type: meta_tests
      score: 1
    -
      key: KAM_MSNBR_REDIR
      rule_type: uri_tests
      score: 5
    -
    ...

=back

=back

=cut

sub get_symbolic_test_names {
    my ( $args, $result ) = @_;

    # Gather Rule Types (Categories)
    my @rule_types = _get_sa_rule_types();
    my %rule_keys;

    foreach my $rule_type (@rule_types) {
        my @type_rule_keys = _get_sa_rule_keys($rule_type);
        my %cur_rule_keys  = map { $_ => $rule_type } @type_rule_keys;
        %rule_keys = ( %rule_keys, %cur_rule_keys );
    }

    # Build Scores List
    my $scores     = _get_sa_scores();
    my @score_keys = sort grep { index( $_, '__' ) != 0 } keys %$scores;
    my @data       = map {
        {
            "key"       => $_,
            "score"     => $scores->{$_} || '1.0',
            "rule_type" => $rule_keys{$_} ? $rule_keys{$_} : "other_tests"
        }
    } @score_keys;

    $result->data( \@data );

    return 1;

}

=head2 clear_spam_box

Clears the spambox of account and pops of account

=cut

sub clear_spam_box {
    my ( $args, $result ) = @_;

    require Cpanel::Email::Accounts;
    my ( $email_accts_info, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
        'event'   => 'fetch',
        'no_disk' => 1,
    );
    my @accounts;
    for my $domain ( keys %$email_accts_info ) {
        for my $acct ( keys %{ $email_accts_info->{$domain}{accounts} || {} } ) {
            push @accounts, $acct . '@' . $domain;
        }
    }
    require Cpanel::Dovecot::Utils;
    foreach my $account ( $Cpanel::user, @accounts ) {

        #Normally this will die(), but we mine for errors and messages just in case.
        my $resp = Cpanel::Dovecot::Utils::expunge_mailbox_messages(
            'account' => $account,
            'mailbox' => 'INBOX.spam',
            'query'   => 'all',
            'verbose' => 1,
        );

        $result->raw_message( $resp->{'messages'} ) if length $resp->{'messages'};
        $result->raw_error( $resp->{'errors'} )     if length $resp->{'errors'};
    }

    return 1;
}

# abstracted for test mocking

my $spam_assasin_config;

sub _sa_config {
    if ($spam_assasin_config) {
        return $spam_assasin_config;
    }

    require Mail::SpamAssassin;

    my $ms = Mail::SpamAssassin->new();
    $ms->init(1);
    $spam_assasin_config = $ms->{conf};

    return $spam_assasin_config;
}
sub _get_sa_rule_types { return _sa_config()->get_rule_types(); }

sub _get_sa_rule_keys {
    my ($rule_type) = @_;
    return _sa_config()->get_rule_keys($rule_type);
}

sub _get_sa_scores { return _sa_config()->{scores}; }

1;
