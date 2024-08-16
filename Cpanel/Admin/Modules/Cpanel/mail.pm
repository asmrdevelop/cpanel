#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Cpanel/Admin/Modules/Cpanel/mail.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Admin::Modules::Cpanel::mail;

=encoding utf-8

=head1 FUNCTIONS

=cut

use cPstrict;

use parent qw( Cpanel::Admin::Base );

use Cpanel::Exception ();

sub _init {
    my ($self) = @_;

    $self->cpuser_has_feature_or_die('popaccts');

    return;
}

# XXX Please don’t add to this list.
use constant _actions__pass_exception => (
    'PURGE_CONNECTIONS',
    'CLEAR_AUTH_CACHE',
    'REBUILD_DOVECOT_SNI',
    'SUSPEND_OUTGOING',
    'UNSUSPEND_OUTGOING',
    'HOLD_OUTGOING',
    'RELEASE_OUTGOING',
    'GET_HELD_MESSAGE_COUNT',
    'DELETE_HELD_MESSAGES',
    'GET_DOMAIN_MAIL_IPS',
    'UPDATE_UTF8MAILBOX_SETTING',
);

# Add to this list instead.
use constant _actions => (
    'TRACE_DELIVERY',
    'TERMINATE_MAILBOX_SESSIONS',
    'SET_MANUAL_MX_REDIRECTS',
    'UNSET_MANUAL_MX_REDIRECTS',

    _actions__pass_exception(),
);

#Override to allow execution of resetpass.cgi during password changes
use constant _allowed_parents => (
    __PACKAGE__->SUPER::_allowed_parents(),
    '/usr/local/cpanel/base/resetpass.cgi',
);

#----------------------------------------------------------------------

sub TRACE_DELIVERY {
    my ( $self, $operator, $recipient ) = @_;

    require Cpanel::Validate::EmailRFC;
    require Cpanel::EximTrace;
    require Cpanel::AccessControl;

    $self->whitelist_exceptions(
        [
            'Cpanel::Exception::InvalidParameter',
            'Cpanel::Exception::UserNotFound',
        ],
        sub {
            Cpanel::Validate::EmailRFC::is_valid_remote_or_die($recipient);

            Cpanel::AccessControl::verify_user_access_to_account(
                $self->get_caller_username() => $operator,
            );
        },
    );

    local $ENV{'REMOTE_USER'} = $operator;

    return Cpanel::EximTrace::deep_trace($recipient);
}

sub PURGE_CONNECTIONS {
    my ( $self, $email ) = @_;

    $self->_validate_access_to_email($email);

    require Cpanel::Session::SinglePurge;
    require Cpanel::Dovecot::Utils;

    # CPANEL-6797: Flush the cache before we kick them
    # to ensure they cannot just log back in
    Cpanel::Dovecot::Utils::flush_auth_caches($email);
    Cpanel::Dovecot::Utils::kick($email);

    Cpanel::Session::SinglePurge::purge_user( $email, 'PURGE_CONNECTIONS' );

    require Cpanel::Services::Cpsrvd;
    Cpanel::Services::Cpsrvd::signal_users_cpsrvd_to_reload(
        $self->get_cpuser_uid(),
        services => ['webmaild'],
    );

    return 1;
}

sub CLEAR_AUTH_CACHE {
    my ( $self, $email ) = @_;

    $self->_validate_access_to_email($email);

    require Cpanel::Dovecot::FlushAuthQueue::Adder;
    require Cpanel::ServerTasks;
    Cpanel::Dovecot::FlushAuthQueue::Adder->add($email);
    Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 10, 'flush_dovecot_auth_cache' );

    return 1;
}

sub _validate_email_address {
    my ( $self, $email ) = @_;
    require Cpanel::Validate::EmailCpanel;
    if ( !Cpanel::Validate::EmailCpanel::is_valid($email) ) {
        die Cpanel::Exception::create( 'InvalidParameter', "Please use a valid email format." );
    }
    return;
}

sub _validate_access_to_email {
    my ( $self, $email ) = @_;
    require Cpanel::AcctUtils::Lookup::MailUser::Exists;
    my $access_yn = Cpanel::AcctUtils::Lookup::MailUser::Exists::does_mail_user_exist($email);
    require Cpanel::AccessControl;
    $access_yn &&= Cpanel::AccessControl::user_has_access_to_account( $self->get_caller_username, $email );

    if ( !$access_yn ) {
        die Cpanel::Exception::create( 'Email::AccountNotFound', [ name => $email ] );
    }
    return 1;
}

sub REBUILD_DOVECOT_SNI {
    my ($self) = @_;

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::schedule_task( ['DovecotTasks'], 120, 'build_mail_sni_dovecot_conf', 'reloaddovecot' );

    return 1;
}

=head2 SUSPEND_OUTGOING

Suspends outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item email - string - The email account to suspend

=back

=head3 Returns

Returns 1 if the email is successfully suspended, undef if it is already suspended, or dies.

=cut

sub SUSPEND_OUTGOING {
    my ( $self, $email ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    my $user = $self->get_caller_username;
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::suspend_mailuser_outgoing_email( 'user' => $user, 'email' => $email );
}

=head2 SUSPEND_OUTGOING

Unsuspends outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item email - string - The email account to unsuspend

=back

=head3 Returns

Returns 1 if the email is successfully unsuspended, undef if it is not suspended, or dies.

=cut

sub UNSUSPEND_OUTGOING {
    my ( $self, $email ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    my $user = $self->get_caller_username;
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::unsuspend_mailuser_outgoing_email( 'user' => $user, 'email' => $email );
}

=head2 HOLD_OUTGOING

Holds outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item email - string - The email account to hold

=back

=head3 Returns

Returns 1 if the email is successfully held, undef if it is already withheld, or dies.

=cut

sub HOLD_OUTGOING {
    my ( $self, $email ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    my $user = $self->get_caller_username;
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::hold_mailuser_outgoing_email( 'user' => $user, 'email' => $email );
}

=head2 RELEASE_OUTGOING

Releases outgoing email messages for an email subaccount.

=head3 Arguments

=over 4

=item email - string - The email account to hold

=back

=head3 Returns

Returns 1 if the email is successfully released, undef if it is not withheld, or dies.

=cut

sub RELEASE_OUTGOING {
    my ( $self, $email ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    my $user = $self->get_caller_username;
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::release_mailuser_outgoing_email( 'user' => $user, 'email' => $email );
}

=head2 GET_HELD_MESSAGE_COUNT

Gets the count of outbound email messages that are being held in the mail queue for the specified email address

=head3 Arguments

=over 4

=item email - string - The email subaccount to get the count for

=back

=head3 Returns

This function returns the count of held messages or dies.

=cut

sub GET_HELD_MESSAGE_COUNT {
    my ( $self, $email ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::get_mailuser_outgoing_email_hold_count( 'email' => $email );
}

=head2 DELETE_HELD_MESSAGES

Queues a background process that deletes outbound email messages that are being held in the mail queue for the specified email address.

=head3 Arguments

=over 4

=item email - string - The email subaccount to delete the held messages for

=back

=head3 Returns

This function returns the count of held messages queued for delete or dies.

=cut

sub DELETE_HELD_MESSAGES {
    my ( $self, $email, $release_after_delete ) = @_;
    $self->_validate_email_address($email);
    $self->_validate_access_to_email($email);
    my $user = $self->get_caller_username;
    require Whostmgr::Accounts::Email;
    return Whostmgr::Accounts::Email::delete_mailuser_outgoing_email_holds( 'email' => $email, 'release_after_delete' => $release_after_delete, 'user' => $user );
}

=head2 $domain_ip_hr = GET_DOMAIN_MAIL_IPS( \@DOMAINS )

Gets the IP addresses that mail from the specified @DOMAINS is sent from.

=over 2

=item Input

=over 3

=item C<ARRAYREF>

The domains to get the IPs for.

=back

=item Output

=over 3

=item C<HASHREF>

Same return as C<Cpanel::DIp::Mail::get_public_mail_ips_for_domains()>.

=back

=back

=cut

sub GET_DOMAIN_MAIL_IPS {
    my ( $self, $domains ) = @_;
    $self->verify_that_cpuser_owns_domain($_) for @$domains;
    require Cpanel::DIp::Mail;
    return Cpanel::DIp::Mail::get_public_mail_ips_for_domains($domains);
}

sub UPDATE_UTF8MAILBOX_SETTING {
    my ( $self, $action ) = @_;

    require Cpanel::Config::CpUserGuard;
    my $conf = Cpanel::Config::CpUserGuard->new( $self->get_caller_username() );
    return 0 if !$conf;
    $conf->{'data'}->{'UTF8MAILBOX'} = $action ? 1 : 0;

    $conf->save() or return 0;

    require Cpanel::Dovecot::Action;
    Cpanel::Dovecot::Action::flush_all_auth_caches_for_user( $self->get_caller_username() );

    return 1;
}

sub TERMINATE_MAILBOX_SESSIONS {
    my ( $self, $action ) = @_;

    my $username = $self->get_caller_username();

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['DovecotTasks'], "flush_entire_account_dovecot_auth_cache_then_kick $username" );

    return 1;
}

sub SET_MANUAL_MX_REDIRECTS ( $self, $redirects_hr ) {

    $self->verify_that_cpuser_owns_domain($_) for keys %$redirects_hr;

    require Cpanel::Exim::ManualMX;
    return Cpanel::Exim::ManualMX::set_manual_mx_redirects($redirects_hr);
}

sub UNSET_MANUAL_MX_REDIRECTS ( $self, $domains_ar ) {

    $self->verify_that_cpuser_owns_domain($_) for @$domains_ar;

    require Cpanel::Exim::ManualMX;
    return Cpanel::Exim::ManualMX::unset_manual_mx_redirects($domains_ar);
}

1;
