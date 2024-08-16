package Cpanel::APNS::Mail::DB;

# cpanel - Cpanel/APNS/Mail/DB.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::APNS::Mail::DB::Sqlite ();
use Cpanel::SQLite::Compat         ();

=encoding utf-8

=head1 NAME

Cpanel::APNS::Mail::DB

=head1 SYNOPSIS

    my $db = Cpanel::APNS::Mail::DB->new();

    $db->set_registrations(
      {
        'aps_device_token' => 'ABC',
        'aps_account_id'   => '000',
        'dovecot_username' => 'bob',
        'dovecot_mailbox'  => 'INBOX',
        'register_time'    => $now
      },
      {
        'aps_device_token' => 'DEF',
        'aps_account_id'   => '123',
        'dovecot_username' => 'fred',
        'dovecot_mailbox'  => 'INBOX',
        'register_time'    => $now
      }
    );

    $db->get_registrations_for_username_and_mailbox('bob@cpanel.net','INBOX');

    $db->purge_registrations_older_than(5);

=head1 DESCRIPTION

This module abstracts handling to the APNS sqlite database.

=head1 FUNCTIONS

=cut

sub new {
    my ($class) = @_;

    my $dbh = Cpanel::APNS::Mail::DB::Sqlite->dbconnect();

    #At one point we were writing these DBs in non-WAL.
    #This conversion will auto-upgrade those.
    Cpanel::SQLite::Compat::upgrade_to_wal_journal_mode_if_needed($dbh);

    return bless { 'dbh' => $dbh }, $class;
}

=head2 set_registrations

Update the list of registered aps devices for a specific user and mailbox.

=over

=item Input

An Array of Hashrefs. Each hashref must contain:

=over 3

=item aps_device_token: The apple device token (ex. AB4C....)

=item aps_account_id:   The apple account id (ex AD4-...)

=item dovecot_username: The dovecot username for the mailbox

=item dovecot_mailbox:  The dovecot mailbox (ex INBOX)

=item register_time:    The time that the registration was made (used for expiry)

=back

=item Output

Returns 1


=back

=cut

sub set_registrations {
    my ( $self, @registrations ) = @_;
    my $rr = $self->{'dbh'}->prepare("REPLACE INTO registrations (aps_device_token,aps_account_id,dovecot_username,dovecot_mailbox,register_time) VALUES(?,?,?,?,?);");
    foreach my $reg (@registrations) {
        $rr->execute(
            $reg->{'aps_device_token'},
            $reg->{'aps_account_id'},
            $reg->{'dovecot_username'},
            $reg->{'dovecot_mailbox'},
            $reg->{'register_time'}
        );
    }
    return $rr->finish();

}

=head2 get_registrations_for_username_and_mailbox

Returns a hashref of registrations indexed by
the APS device token

=over

=item Input

=over

=item C<SCALAR>

    The dovecot username (Ex. bob@cpanel.net)

=item C<SCALAR>

    The dovecot mailbox (Ex. INBOX)

=back

=item Output

=item C<HASHREF>

A hashref indexed by device tokens in the following format:

    {
        'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890' => {
            'aps_account_id'   => '456',
            'aps_device_token' => 'ABC'
        },
        ....
    },

=back

=cut

sub get_registrations_for_username_and_mailbox {
    my ( $self, $dovecot_username, $dovecot_mailbox ) = @_;

    return $self->{'dbh'}->selectall_hashref( "select aps_device_token, aps_account_id from registrations where dovecot_username=? and dovecot_mailbox=?;", 'aps_device_token', {}, $dovecot_username, $dovecot_mailbox );

}

=head2 purge_registrations_older_than

Delete registrations from the database that are older then X days

=over

=item Input

=over

=item C<SCALAR>

    The number of days back to keep registrations

=back

=item Output

=over

=item Returns 1 if registrations exist.

=item Returns 0 if no registrations exist.

=back

=back

=cut

sub purge_registrations_older_than {
    my ( $self, $days ) = @_;

    my $row = $self->{'dbh'}->selectcol_arrayref( "select name from sqlite_master where type='table' and name=? /*table_exists*/;", {}, 'registrations' );
    if ( $row && $row->[0] ) {
        my $eq = $self->{'dbh'}->prepare("delete from registrations where register_time < ?;");
        $eq->execute( time() - ( 86000 * $days ) );
        return $eq->finish();
    }

    return 0;
}

1;
