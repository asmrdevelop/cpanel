package Cpanel::SSL::Notify;

# cpanel - Cpanel/SSL/Notify.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Notify - Logic for SSL notifications

=cut

#----------------------------------------------------------------------

use Cpanel::Set ();

use constant _ALL_INTERVALS => [ 30, 20, 10, 5, 0, -1, -2, -3 ];

use constant {
    _ONE_DAY => 86400,

    _LOCAL_INTERVALS  => _ALL_INTERVALS(),
    _REMOTE_INTERVALS => [ @{ _ALL_INTERVALS() }[ 1 .. $#{ _ALL_INTERVALS() } ] ],
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $level = get_next_notification_level_to_send_for_local($SECONDS_LEFT, @SENT)

Returns an opaque scalar that identifies the notification to send.
This scalar should be recorded in a list of “already-sent” notifications.

$SECONDS_LEFT is the number of validity seconds left for the relevant
certificate. @SENT is the list of $level returns that have already been
sent.

=cut

sub get_next_notification_level_to_send_for_local ( $secs_left, @sent ) {
    return _get_next_notification_level( $secs_left, \@sent, _LOCAL_INTERVALS() );
}

sub get_next_notification_level_to_send_for_linked_node ( $secs_left, @sent ) {
    return _get_next_notification_level( $secs_left, \@sent, _REMOTE_INTERVALS() );
}

sub _get_next_notification_level ( $secs_left, $sent_ar, $intervals_ar ) {    ## no critic qw(ProhibitManyArgs) - misparse
    my $days_left = $secs_left / _ONE_DAY();

    if ( $days_left <= $intervals_ar->[0] ) {
        my @intervals_left = Cpanel::Set::difference(
            $intervals_ar,
            $sent_ar,
        );

        foreach my $notify_time (@intervals_left) {

            # It doesn't matter which one as we only care if we need to.
            # Once we notify the next time will be set to later so we won't do it again until we trigger the next interval
            if ( $days_left <= $notify_time ) {
                return $notify_time;

            }
        }
    }

    return undef;    # No notification to send
}

1;
