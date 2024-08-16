package Cpanel::Email::Accounts::HoldMaintenance;

# cpanel - Cpanel/Email/Accounts/HoldMaintenance.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Email::Accounts::HoldMaintenance

=head1 SYNOPSIS

use Cpanel::Email::Accounts::HoldMaintenance ();

Cpanel::Email::Accounts::HoldMaintenance::remove_hold_files_for_sender('email@domain.com')

=head1 DESCRIPTION

Methods for maintaining the held message index for senders

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Autodie                ();
use Cpanel::Email::Accounts::Paths ();
use Cpanel::Exception              ();
use Cpanel::FileUtils::Dir         ();

=head2 remove_hold_files_for_sender

Removes the touch files that track held messages for a sender if the message is no longer queued in Exim.

=head3 Arguments

=over 4

=item sender - string - The email subaccount to delete the held message index files for

=back

=head3 Exceptions

=over

=item - If sender isn't passed

=back

=cut

sub remove_hold_files_for_sender {

    my ($sender) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'sender' ] ) if !length $sender;

    my $sender_dir = $Cpanel::Email::Accounts::Paths::EMAIL_HOLDS_BASE_PATH . '/' . $sender;

    my $msgid_count = 0;
    foreach my $msgid ( @{ Cpanel::FileUtils::Dir::get_directory_nodes($sender_dir) } ) {
        if ( !_exim_msgid_exists_in_queue($msgid) ) {
            if ( Cpanel::Autodie::unlink_if_exists("$sender_dir/$msgid") ) {
                print "Removed “$msgid” for “$sender”.\n";
            }

            next;
        }
        $msgid_count++;
    }
    if ( !$msgid_count ) {

        # ENOTEMPTY is OK since another message may have been delivered between
        # when we read the dir and when we try to remove it.  It will just be
        # removed next time.
        rmdir($sender_dir) or do {
            warn "rmdir($sender_dir): $!" if !$!{'ENOTEMPTY'};
        };
    }

    return;
}

sub _exim_msgid_exists_in_queue {
    my ($msgid) = @_;

    # 1fC3NO-0004Af-Lr-D
    return -e $Cpanel::Email::Accounts::Paths::EXIM_QUEUE_INPUT_DIR . '/' . substr( $msgid, 5, 1 ) . '/' . $msgid . '-H';
}

1;
