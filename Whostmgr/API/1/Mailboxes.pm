package Whostmgr::API::1::Mailboxes;

# cpanel - Whostmgr/API/1/Mailboxes.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Exception       ();
use Cpanel::Dovecot::Utils  ();
use Whostmgr::API::1::Utils ();

use constant NEEDS_ROLE => 'MailReceive';

=encoding utf-8

=head1 NAME

Cpanel::API::Mailboxes - Thin wrappers around dovecot's mailbox functions

=head1 SYNOPSIS

CLI:

    whmapi1 get_mailbox_status_list account=izzy@izzy.org

=head1 DESCRIPTION

This module contains functions for examining and modifing mailboxes.

=cut

sub get_mailbox_status ( $args, $metadata, $api_args ) {

    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );

    my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
    return $remote if $remote;

    my $mailboxes = Cpanel::Dovecot::Utils::get_mailbox_status($account);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return $mailboxes;
}

=head2 get_mailbox_status_list

Return the status of all mailboxes belonging to an account.

=over 2

=item Input

=over 3

=item C<HASHREF>

=over 3

=item account (required) - The account to get the mailbox status for

=back

=back

=item Output

=over 3

=item C<HASHREF>

  The data will be formatted similar to:

  mailboxes:
    -
      guid: '...',
      mailbox: INBOX.Junk
      messages: 69
      vsize: 25251580
    -
      guid: '...',
      mailbox: INBOX.checkhtmlparser
      messages: 0
      vsize: 0
    -
      guid: '...',
      mailbox: INBOX.Drafts
      messages: 0
      vsize: 0
    -
      guid: '...',
      mailbox: INBOX.imap
      messages: 0
      vsize: 0
    ...


=back

=back

=cut

sub get_mailbox_status_list ( $args, $metadata, $api_args ) {

    my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
    return $remote if $remote;

    my $mailboxes = get_mailbox_status( $args, $metadata, $api_args );

    return {
        mailboxes => [
            map { ( { %{ $mailboxes->{$_} }, 'mailbox' => $_ } ) }
              keys %$mailboxes

        ]
    };
}

sub expunge_mailbox_messages ( $args, $metadata, $api_args ) {

    my $mailbox = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'mailbox' );

    my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
    return $remote if $remote;

    return _expunge_mailbox_messages( $args, $metadata, 'expunge_mailbox_messages', mailbox => $mailbox );
}

sub expunge_messages_for_mailbox_guid ( $args, $metadata, $api_args ) {

    my $mb_guid = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'mailbox_guid' );

    my $remote = _proxy_this_api_call( $args, $metadata, $api_args );
    return $remote if $remote;

    return _expunge_mailbox_messages( $args, $metadata, 'expunge_messages_for_mailbox_guid', mailbox_guid => $mb_guid );
}

sub terminate_cpuser_mailbox_sessions ( $args, $metadata, @ ) {
    my $username = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'username' );

    require Cpanel::Config::HasCpUserFile;
    if ( !Cpanel::Config::HasCpUserFile::has_cpuser_file($username) ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $username ] );
    }

    require Cpanel::ServerTasks;
    Cpanel::ServerTasks::queue_task( ['DovecotTasks'], "flush_entire_account_dovecot_auth_cache_then_kick $username" );

    $metadata->set_ok();

    return;
}

#----------------------------------------------------------------------

sub _proxy_this_api_call ( $args, @other_args ) {
    my $fn = ( caller 1 )[3] =~ s<.+::><>r;

    # This works because all of the API calls that call this function
    # accept an “account” argument.
    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );

    require Whostmgr::API::1::Utils::Proxy;
    my $remote = Whostmgr::API::1::Utils::Proxy::proxy_if_configured(
        function       => $fn,
        perl_arguments => [ $args, @other_args ],
        worker_type    => 'Mail',
        account_name   => $account,
    );

    return $remote && $remote->get_raw_data();
}

sub _expunge_mailbox_messages {
    my ( $args, $metadata, $func_name, @args ) = @_;

    my $account = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'account' );
    my $query   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'query' );

    my $ref = Cpanel::Dovecot::Utils->can($func_name)->(
        'account' => $account,
        'query'   => $query,
        'verbose' => 1,
        @args,
    );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return $ref;
}

1;
