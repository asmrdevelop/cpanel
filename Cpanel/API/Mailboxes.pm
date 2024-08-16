package Cpanel::API::Mailboxes;

# cpanel - Cpanel/API/Mailboxes.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::API::Mailboxes - Thin wrappers around dovecot's mailbox functions

=head1 SYNOPSIS

    use Cpanel::API::Mailboxes;
    my $result = Cpanel::API::execute_or_die('Mailboxes','get_mailbox_status_list', {'account'=>'bob'}) ;
    my $result = Cpanel::API::execute_or_die('Mailboxes',"expunge_mailbox_messages", {'account'=>'bob', 'mailbox' =>'INBOX.Cron', 'query' => 'savedbefore 2w'});

    CLI:

    uapi -u <cpanel_user> Mailboxes get_mailbox_status_list account=user@domain.tld
    uapi -u <cpanel_user> Mailboxes expunge_mailbox_messages account=user@domain.tld mailbox=INBOX.Cron query='savedbefore 2w'

    Template:

    [% result = execute_or_die("Mailboxes","get_mailbox_status_list", {'account'=>'bob'}) %]
    [% Dumper.dump_html(result) %]
    [% result = execute_or_die("Mailboxes","expunge_mailbox_messages", {'account'=>'bob', 'mailbox' =>'INBOX.Cron', 'query' => 'savedbefore 2w'}) %]
    [% Dumper.dump_html(result) %]

=head1 DESCRIPTION

This module contains functions for examining and modifing mailboxes.

=cut

use strict;
use warnings;

use Cpanel::Dovecot::Utils         ();
use Cpanel::Email::Accounts        ();
use Cpanel::Security::Authz        ();
use Cpanel::Config::LoadCpUserFile ();

=head2 get_mailbox_status_list

Return the status of all mailboxes belonging to an account.

=over 2

=item Input

=over 3

=item C<Cpanel::Args>

=over 3

=item account (required) - The account to get the mailbox status for,
e.g., C<bob>, C<mail@bob.com>, etc.

=back

=back

=item Output

=over 3

=item C<Cpanel::Result>

    The data will be formatted similar to:

    -
      guid: b7a359119e771b58484a0000a841250d
      mailbox: INBOX.Junk
      messages: 69
      vsize: 25251580
    -
      guid: 6a0c7508791db758db3b0000a841250d
      mailbox: INBOX.checkhtmlparser
      messages: 0
      vsize: 0
    -
      guid: 826d891e808fb058895a0000a841250d
      mailbox: INBOX.Drafts
      messages: 0
      vsize: 0
    -
      guid: 12ad121c234ffd5738050000a841250d
      mailbox: INBOX.imap
      messages: 0
      vsize: 0
    ...


=back

=back

=cut

sub get_mailbox_status_list {
    my ( $args, $result ) = @_;

    my $account = $args->get_length_required('account');
    if ( $Cpanel::appname eq 'webmail' ) { $account = $Cpanel::authuser }
    Cpanel::Security::Authz::verify_user_has_access_to_account( $Cpanel::user, $account );
    my $mailbox_ref = Cpanel::Dovecot::Utils::get_mailbox_status($account);

    #For cpuser default accounts, we don’t want to show the pseudo-folders
    #that get created for maildir when an email account is created.
    if ( -1 == index( $account, '@' ) ) {
        my ( $popaccts_ref, $_manage_err ) = Cpanel::Email::Accounts::manage_email_accounts_db(
            'event'   => 'fetch',
            'no_disk' => 1,
        );
        if ( !$popaccts_ref ) {
            die $_manage_err || 'Unknown error in fetching email accounts';
        }

        for my $mailbox ( keys %$mailbox_ref ) {
            my ( $local, $domain ) = split m<@>, $mailbox;

            # get_mailbox_status uses doveadm, and doveadm gives these local parts back with '_' represented as '__'.
            # However, for the $popaccts_ref lookup below, we want just one underscore.
            $local =~ s{__}{_}g;

            next if !length $domain;
            next if $local !~ s<\AINBOX\.><>;

            $domain =~ tr<_><.>;
            next if !$popaccts_ref->{$domain};
            next if !$popaccts_ref->{$domain}{'accounts'}{$local};

            delete $mailbox_ref->{$mailbox};
        }
    }

    $result->data(
        [

            map { ( { %{ $mailbox_ref->{$_} }, 'mailbox' => $_ } ) } keys %$mailbox_ref

        ]
    );

    return 1;
}

=head2 expunge_messages_for_mailbox_guid

Delete messages in a mailbox.

Inputs are:

=over

=item * C<account> (required) - The account to operate on, e.g., C<bob>, C<mail@bob.com>, etc.

=item * C<query> (required) - The dovecot query to execute (see doveadm-search-query: L<http://wiki2.dovecot.org/Tools/Doveadm/SearchQuery>)

=item *  C<mailbox_guid> (required) - The GUID of the mailbox to operate on. Mailbox GUIDs are given in the
return of C<get_mailbox_status_list()>.

=back

C<query> is required in order to prevent accidental removal of all messages in the mailbox.

This function exists also in WHM API v1.

=cut

sub expunge_messages_for_mailbox_guid {
    my ( $args, $result ) = @_;

    my $mb_guid = $args->get_length_required('mailbox_guid');

    return _expunge_mailbox_messages( $args, $result, 'expunge_messages_for_mailbox_guid', mailbox_guid => $mb_guid );
}

=head2 expunge_mailbox_messages

The same function as C<expunge_messages_for_mailbox_guid>,
but instead of C<mailbox_guid>, it accepts:

=over

=item * C<mailbox> - A pattern to match for mailboxes whose mail to delete.
This pattern treats C<*> and C<?> as their familiar wildcard values.

=back

This function exists also in WHM API v1.

=cut

sub expunge_mailbox_messages {
    my ( $args, $result ) = @_;

    my $mb_pattern = $args->get_length_required('mailbox');

    return _expunge_mailbox_messages( $args, $result, 'expunge_mailbox_messages', mailbox => $mb_pattern );
}

=head2 has_utf8_mailbox_names

=head3 Description:

Determines if the UTF-8 mailbox names setting is enabled or disabled for the user.

=head3 Arguments:

=over

=item * C<user>: The name of the user to check. Default: The currently logged in cPanel user.

=back

=head3 Returns:

=over

=item Hash with the following structure.

=over

=item * C<enabled>: boolean - truthy if enabled, falsy otherwise.

=back

=back

=cut

sub has_utf8_mailbox_names {
    my ( $args, $result ) = @_;

    my $user = $args->get('user') || $Cpanel::user;
    Cpanel::Security::Authz::verify_user_has_access_to_account( $Cpanel::user, $user );

    my $user_conf = Cpanel::Config::LoadCpUserFile::load_or_die($user);
    my $enabled   = $user_conf->{'UTF8MAILBOX'} ? 1         : 0;
    my $status    = $enabled                    ? "enabled" : "disabled";
    $result->message( '[asis,UTF8MAILBOX] is [_1] for user [_2].', $status, $user );
    $result->data( { enabled => $enabled } );
    return 1;
}

=head2 set_utf8_mailbox_names

=head3 Description

Sets the UTF-8 mailbox names setting for the user.

=head3 Arguments

=over

=item * C<user>: The name of the user to set. Default: The currently logged in cPanel user.

=back

=head3 Returns:

=over

=item Hash with the following structure.

=over

=item * C<success>: boolean - truthy if the call was a success, falsy otherwise.

=back

=back

=cut

sub set_utf8_mailbox_names {
    my ( $args, $result ) = @_;

    my $enabled = $args->get_length_required('enabled') ? 1 : 0;

    require Cpanel::AdminBin::Call;
    if ( Cpanel::AdminBin::Call::call( 'Cpanel', 'mail', 'UPDATE_UTF8MAILBOX_SETTING', $enabled ) ) {
        $result->data( { success => 1 } );
        $result->message( 'Updated user setting [asis,UTF8MAILBOX] to: [_1]', $enabled );
        return 1;
    }

    $result->data( { success => 0 } );
    $result->error( 'Failed to update user setting [asis,UTF8MAILBOX] to: [_1]', $enabled );
    return;
}

#----------------------------------------------------------------------

sub _expunge_mailbox_messages {
    my ( $args, $result, $func_name, @args ) = @_;

    my $account = $args->get_length_required('account');
    if ( $Cpanel::appname eq 'webmail' ) { $account = $Cpanel::authuser }
    Cpanel::Security::Authz::verify_user_has_access_to_account( $Cpanel::user, $account );

    my $query = $args->get_length_required('query');

    #Normally this will die(), but we mine for errors and messages just in case.
    my $resp = Cpanel::Dovecot::Utils->can($func_name)->(
        'account' => $account,
        'query'   => $query,
        'verbose' => 1,
        @args,
    );

    $result->raw_message( $resp->{'messages'} ) if length $resp->{'messages'};
    $result->raw_error( $resp->{'errors'} )     if length $resp->{'errors'};

    return 1;
}

my $popaccts_and_email_disk_usage_feature = { needs_feature => { match => 'all', features => [qw(popaccts email_disk_usage)] } };

my $popaccts_feature = { needs_feature => "popaccts" };

our %API = (
    _worker_node_type                 => 'Mail',
    get_mailbox_status_list           => { allow_demo => 1 },
    expunge_messages_for_mailbox_guid => $popaccts_and_email_disk_usage_feature,
    expunge_mailbox_messages          => $popaccts_and_email_disk_usage_feature,
    has_utf8_mailbox_names            => $popaccts_feature,
    set_utf8_mailbox_names            => $popaccts_feature,
);

1;
