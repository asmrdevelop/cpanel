package Cpanel::TailWatch::APNSPush;

# cpanel - Cpanel/TailWatch/APNSPush.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Cpanel::TailWatch::Base';
use Cpanel::OS ();

our $VERSION = 1.0;

=encoding utf-8

=head1 NAME

Cpanel::TailWatch::APNSPush - Notify Apple devices when new mail arrives

=head1 DESCRIPTION

This is a tailwatchd driver for sending APNS notifications
when new email arrives.  It watches the dovecot entries with
XAPS in the maillog and registred them in a sqlite database.
When a NOTIFY entry is seen it looks up the registration in the
database and sends an APNS notification.

=cut

=head2 init

Init the module and loads required perl modules.

=cut

sub init {
    my ($self) = @_;

    # this is where modules should be require()'d
    # this method gets called if PKG->is_enabled()

    require Cpanel::JSON;
    require Cpanel::TailWatch;
    require Cpanel::APNS::Mail::Config;
    require Cpanel::APNS::Mail::DB;
    return 1;
}

=head2 internal_name

Returns the name of the module that is used internally.

=cut

sub internal_name { return 'apnspush'; }

=head2 new

Creates a new object.

=cut

sub new {
    my ( $my_ns, $tailwatch_obj ) = @_;

    if ( !_apns_certs_are_installed() ) {
        $tailwatch_obj->log("APNSPush not enabled because it requires an Apple certificate and key file to be installed.");

        # Return undef is a special case for tailwatchd:
        #
        # We return undef to indicate to tailwatchd that this is not a failure,
        # the module just isn't available so we don't generate an exception in the log
        return undef;
    }

    my $self = bless { 'internal_store' => {} }, $my_ns;

    my $maillog = Cpanel::OS::maillog_path();
    $maillog = $maillog . '.0' if !-f $maillog;
    $maillog = '/var/log/mail' if !-f $maillog;

    $tailwatch_obj->register_module( $self, __PACKAGE__, Cpanel::TailWatch::PREVPNT(), [$maillog] );

    local $@;
    eval { $self->{'apns_db'} = Cpanel::APNS::Mail::DB->new(); };
    if ($@) {
        $tailwatch_obj->log("[SQLERR] Could not connect to Cpanel::APNS::Mail::DB database: $@");
        die;
    }

    $self->{'process_line_regex'}->{$maillog} = qr/ XAPS /;

    return $self;
}

=head2 process_line

Process a line from the maillog by registering a new client
or sending a notification for new mail.

=over 2

=item Input

=over 3

=item C<SCALAR>

    The line to process

=item C<OBJECT>

    The master tailwatch object

=back

=item Output

Nothing

=back

=cut

sub process_line {
    my ( $self, $line, $tailwatch_obj, $logfile, $now ) = @_;

    if ( $line =~ m/dovecot: [a-zA-Z]+\(([^)]+)\).*?: XAPS (REGISTER|NOTIFY) (\{.*)/ ) {
        my ( $user, $type, $json_text ) = ( $1, $2, $3 );
        local $@;
        my $json = eval { Cpanel::JSON::Load($json_text) };
        if ($@) {
            $tailwatch_obj->log("Error parsing JSON in XAPS $type: $@");
            return;
        }
        elsif ( $type eq 'NOTIFY' ) {
            return $self->_process_xaps_notify( $tailwatch_obj, $user, $json, $now );
        }
        elsif ( $type eq 'REGISTER' ) {
            return $self->_process_xaps_register( $tailwatch_obj, $user, $json, $now );
        }
    }

    return;
}

sub _connect_apns {
    my ($self) = @_;

    require Cpanel::APNS if !$INC{'Cpanel/APNS.pm'};
    $self->{'apns'} = Cpanel::APNS->new(
        {
            cert => Cpanel::APNS::Mail::Config::CERT_FILE(),
            key  => Cpanel::APNS::Mail::Config::KEY_FILE()
        }
    );
    return 1;

}

sub _send_to_apns_with_retry {
    my ( $self, $token, $payload ) = @_;

    $self->_connect_apns() if !$self->{'apns'};

    return $self->{'apns'}->write_payload( $token, $payload );
}

sub _log_xaps_register_param_invalid {
    my ( $self, $tailwatch_obj, $param_name, $param_value ) = @_;

    $tailwatch_obj->log("Rejected “$param_name” value “$param_value” while parsing XAPS registeration message");

    return 0;
}

sub _process_xaps_register {
    my ( $self, $tailwatch_obj, $user, $json, $now ) = @_;

    if ( $json->{'aps-device-token'} =~ tr{A-Za-z0-9}{}c ) {
        return $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'aps-device-token', $json->{'aps-device-token'} );
    }
    elsif ( $json->{'aps-account-id'} =~ tr{A-Za-z0-9-}{}c ) {
        return $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'aps-account-id', $json->{'aps-account-id'} );
    }
    elsif ( $json->{'dovecot-username'} =~ tr[~{}_^?=$#!.A-Za-z0-9@-][]c ) {
        return $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'dovecot-username', $json->{'dovecot-username'} );
    }

    $now ||= time();

    if ( ref $json->{'dovecot-mailboxes'} eq 'ARRAY' ) {
        my @registrations;
        foreach my $mailbox ( @{ $json->{'dovecot-mailboxes'} } ) {
            if ( $mailbox =~ tr{'"}{} ) {
                $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'dovecot-mailboxes', $mailbox );
                next;
            }
            my $normalized_mailbox = $self->_normalize_mailbox_name($mailbox);
            push @registrations, {
                'aps_device_token' => $json->{'aps-device-token'},
                'aps_account_id'   => $json->{'aps-account-id'},
                'dovecot_username' => $json->{'dovecot-username'},
                'dovecot_mailbox'  => $normalized_mailbox,
                'register_time'    => $now
            };
        }
        $self->{'apns_db'}->set_registrations(@registrations);
    }
    else {
        $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'dovecot-mailboxes', $json->{'dovecot-mailboxes'} );
    }
    return 1;
}

sub _process_xaps_notify {
    my ( $self, $tailwatch_obj, $user, $json ) = @_;

    my $dovecot_mailbox  = $json->{'dovecot-mailbox'};
    my $dovecot_username = $json->{'dovecot-username'};

    if ( $dovecot_mailbox =~ tr{'"}{} ) {
        return $self->_log_xaps_register_param_invalid( $tailwatch_obj, 'dovecot-mailboxes', $dovecot_mailbox );
    }

    my $normalized_dovecot_mailbox = $self->_normalize_mailbox_name($dovecot_mailbox);

    if ( $normalized_dovecot_mailbox ne 'INBOX' ) {

        # c.f. https://opensource.apple.com/source/dovecot/dovecot-293/dovecot/src/plugins/push-notify/push-notify-plugin.c.auto.html
        # apple ignores all notifications for folders other than INBOX, so let’s not bother sending them
        return 0;
    }

    my $device_tokens = $self->{'apns_db'}->get_registrations_for_username_and_mailbox( $dovecot_username, $normalized_dovecot_mailbox );

    foreach my $token ( keys %{$device_tokens} ) {
        local $@;

        # In theory we could sent notifications for mailboxes other than INBOX but it doesn't actually work
        # Apple ignores all notifications for folders other than INBOX so lets not bother sending them
        #
        # In the future if the 'm' key does work it could be implemented as follows:
        # { aps => { 'account-id' => $device_tokens->{$token}->{'aps_account_id'}, 'm' => [md5_hex('mailbox')] }
        #
        # For more information please see https://github.com/argon/push_notify/blob/master/lib/controller.js
        eval { $self->_send_to_apns_with_retry( $token, { aps => { 'account-id' => $device_tokens->{$token}->{'aps_account_id'} } } ); };
        $tailwatch_obj->log("Error sending APNS notification: $@") if $@;
    }

    return 1;
}

sub _normalize_mailbox_name {
    my ( $self, $mailbox ) = @_;

    # Depending on the version of iOS
    # $mailbox might be:
    # INBOX, Notes, INBOX/Notes, INBOX.Notes, cow, pig, cow.pig, INBOX.cow, INBOX.cow.pig, INBOX/cow.pig, INBOX.cow/pig, ...
    # Normalized will always be:
    # INBOX, INBOX.Folder, INBOX.Folder.SubFolder, ...
    return 'INBOX' if $mailbox eq 'INBOX';
    #
    $mailbox =~ tr{/}{.};

    if ( index( $mailbox, 'INBOX.' ) != 0 ) {
        substr( $mailbox, 0, 0, 'INBOX.' );
    }

    return $mailbox;
}

sub _apns_certs_are_installed {
    return ( -s Cpanel::APNS::Mail::Config::CERT_FILE() && -s Cpanel::APNS::Mail::Config::KEY_FILE() ) ? 1 : 0;
}

1;
