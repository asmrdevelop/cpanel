package Cpanel::SSL::Notify::LinkedNodes;

# cpanel - Cpanel/SSL/Notify/LinkedNodes.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Notify::LinkedNodes

=head1 DESCRIPTION

This module contains logic to survey all linked nodes’ SSL
certificates and send notifications as needed.

=cut

#----------------------------------------------------------------------

use AnyEvent     ();
use Promise::ES6 ();

use Cpanel::OpenSSL::Verify                   ();
use Cpanel::LinkedNode::CheckTLS              ();
use Cpanel::SSL::Objects::Certificate         ();
use Cpanel::SSL::Notify                       ();
use Cpanel::SSL::Notify::History::LinkedNodes ();

use constant {
    _NOTIFICATION_TYPE => 'SSL::LinkedNodeCertificateExpiring',

    _VERIFICATION_STATUS_NOTIFICATION_WHITELIST => {
        OK               => 1,
        CERT_HAS_EXPIRED => 1,
    },
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new( %OPTS )

Instantiates this class.

%OPTS are:

=over

=item * C<output> Optional, instance of L<Cpanel::Output>.
Submit this if you want to enable debug mode.

=back

=cut

sub new ( $class, %opts ) {
    return bless {%opts}, $class;
}

#----------------------------------------------------------------------

=head2 $obj = I<OBJ>->enable_debug()

Enables debug mode. Will print various status messages to help
diagnose why notifications are or aren’t being sent.

=cut

sub enable_debug ($self) {
    $self->{'_debug'} = 1;

    return $self;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->notify_all()

Does the bulk of this module’s work: runs a TLS handshake to WHM with all
linked nodes and sends notifications if necessary.

=cut

sub notify_all ($self) {
    my $history = Cpanel::SSL::Notify::History::LinkedNodes->new();

    my $alias_promise_hr = Cpanel::LinkedNode::CheckTLS::verify_linked_nodes_whm();

    for my $alias ( keys %$alias_promise_hr ) {
        $alias_promise_hr->{$alias}->then(
            sub ($status_hr) {

                # Stop if TLS handshake failed (even without verification).
                return if !$self->_check_handshake( $alias, $status_hr );

                return if !$self->_check_verify( $alias, $status_hr );

                my $cert_pem = $status_hr->{'chain'}[0];

                my $cert_obj = Cpanel::SSL::Objects::Certificate->new( cert => $cert_pem );

                my $notify_level = $self->_check_remaining_validity( $alias, $cert_obj, $history );

                if ($notify_level) {
                    _send_notification(
                        {
                            alias       => $alias,
                            certificate => $cert_obj,
                            %{$status_hr}{'hostname'},
                        }
                    );
                }
            }
        );
    }

    # Wait for all of the TLS handshakes to finish:
    my $cv = AnyEvent->condvar();
    Promise::ES6->all( [ values %$alias_promise_hr ] )->then($cv);
    $cv->recv();

    $history->save();

    return;
}

sub _check_handshake ( $self, $alias, $status_hr ) {
    if ($status_hr) {
        $self->_debug("$alias: handshake OK");
        return 1;
    }

    $self->_debug("$alias: handshake failed");

    return 0;
}

sub _check_verify ( $self, $alias, $status_hr ) {
    my $verify_str = Cpanel::OpenSSL::Verify::error_code_to_name( $status_hr->{'handshake_verify'} );

    # Stop if the verification status isn’t recognized.
    if ( _VERIFICATION_STATUS_NOTIFICATION_WHITELIST()->{$verify_str} ) {
        $self->_debug("$alias: verify = $verify_str");
        return 1;
    }

    $self->_debug("$alias: verify ($verify_str) isn’t what we notify on");

    return 0;
}

sub _check_remaining_validity ( $self, $alias, $cert_obj, $history ) {
    my $secs_left = $cert_obj->not_after() - time;

    my $cert_pem = $cert_obj->text();

    my @already_sent = $history->get_sent_notifications($cert_pem);

    $self->_debug("$alias: Already sent = [@already_sent]");

    my $notify_level = Cpanel::SSL::Notify::get_next_notification_level_to_send_for_linked_node( $secs_left, @already_sent );

    # Stop if it’s not time for a notification yet.
    if ( defined $notify_level ) {
        $self->_debug("$alias: Notification level $notify_level");

        $history->record( $cert_pem, $notify_level );

        return $notify_level;
    }
    elsif (@already_sent) {
        $history->retain_notifications($cert_pem);
    }

    $self->_debug("$alias: It’s not time to notify yet.");

    return undef;
}

sub _debug ( $self, $msg ) {
    if ( $self->{'_debug'} ) {
        $self->{'output'}->out($msg);
    }

    return;
}

sub _send_notification ($node_info_hr) {
    require Cpanel::Notify;

    Cpanel::Notify::notification_class(
        'class'            => _NOTIFICATION_TYPE(),
        'application'      => _NOTIFICATION_TYPE(),
        'constructor_args' => [
            node_info => $node_info_hr,
        ],
    );

    return;
}

1;
