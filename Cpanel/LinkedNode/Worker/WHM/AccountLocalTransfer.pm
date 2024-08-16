# cpanel - Cpanel/LinkedNode/Worker/WHM/AccountLocalTransfer.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer;

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer - Encapsulates the logic required to execute an AccountLocal transfer on a linked server node

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer;

    Cpanel::LinkedNode::Worker::WHM::AccountLocalTransfer::execute_account_local_transfer( "nodealias", $username, "/path/to/cpmove-username.tar.gz" );

=head1 DESCRIPTION

This module provides functions to encapsulate the process of starting a transfer session on a linked server
node for cpmove data that resides on the linked server node and watching the session to determine success or
failure.

=head1 FUNCTIONS

=cut

use Cpanel::Exception               ();
use Cpanel::JSON                    ();
use Cpanel::LinkedNode              ();
use Cpanel::LinkedNode::Worker::WHM ();
use Whostmgr::TweakSettings         ();

my $poll_state_frequency = 5;
my $finished_states      = [qw(COMPLETED ABORTED FAILED)];

# Overloadable for testing
sub _poll_state_frequency { return $poll_state_frequency }
sub _finished_states      { return $finished_states }
sub _sleep                { sleep $poll_state_frequency; return; }
sub _time                 { return time }

sub _poll_state_timeout {
    return Whostmgr::TweakSettings::get_conf('Main')->{"transfers_timeout"}{"maximum"} / 2;
}

=head2 execute_account_local_transfer( $alias, $username, $cpmovepath )

Executes an AccountLocal transfer session on the specified node for the specified cpmove data.

=over

=item Input

=over

=item $alias

The alias of the linked node on which to execute the transfer

=item $username

The name of the remote user to create.

=item $cpmovepath

A filesystem path on the linked node for either a cpmove tarball or a directory containing an
extracted cpmove tarball.

=back

=item Output

=over

This function returns nothing on success, dies otherwise.

=back

=back

=cut

sub execute_account_local_transfer ( $node_alias, $username, $cpmovepath ) {

    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( alias => $node_alias );

    my $restore = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => 'start_local_cpmove_restore',
        api_opts => {
            cpmovepath     => $cpmovepath,
            username       => $username,
            delete_archive => 1,

            # We do *NOT* overwrite accounts because we want to avoid
            # a potential conflict with already-existing accounts on the
            # child node that might be for other parent nodes. (As of v96
            # we don’t support multiple parents per child, but we might as
            # well make it easy to add support for that setup later.)
            #
            overwrite => 0,
        }
    );

    my $transfer_session_id = $restore->{transfer_session_id};

    my $transfer_state = "";
    my $s_time         = _time();

    while ( !grep { $transfer_state eq $_ } @{ _finished_states() } ) {

        my $state = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
            node_obj => $node_obj,
            function => "get_transfer_session_state",
            api_opts => {
                transfer_session_id => $transfer_session_id,
            },
        );

        $transfer_state = $state->{state_name};

        last if grep { $transfer_state eq $_ } @{ _finished_states() };

        if ( _time() - $s_time > _poll_state_timeout() ) {
            die Cpanel::Exception->create( "The process timed out while waiting for the remote transfer session “[_1]” to finish.", [$transfer_session_id] );
        }

        _sleep();
    }

    if ( $transfer_state eq "ABORTED" ) {
        die Cpanel::Exception->create( "A user aborted the remote transfer session “[_1]”.", [$transfer_session_id] );
    }
    elsif ( $transfer_state eq "FAILED" ) {
        die Cpanel::Exception->create( "The remote transfer session “[_1]” failed.", [$transfer_session_id] );
    }

    # It’s possible that the transfer ended in a COMPLETED state but that the AccountLocal transfer
    # item itself failed, so we need to check the log to see that the item was actually successful.
    my $log_data = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => "fetch_transfer_session_log",
        api_opts => {
            transfer_session_id => $transfer_session_id,
            logfile             => "master.log",
        },
    );

    # The log data is returned as individual JSON structs for each line in the log
    # rather than just returning as a JSON array.
    foreach my $line_json ( split /\n/, $log_data->{log} ) {

        my $line_hr = Cpanel::JSON::Load($line_json);

        if ( $line_hr->{contents}{item_type} && $line_hr->{contents}{item_type} eq 'AccountUpload' && $line_hr->{contents}{action} eq 'failed-item' ) {
            die Cpanel::Exception->create_raw( $line_hr->{contents}{msg}{failure} );
        }

    }

    return;
}

1;
