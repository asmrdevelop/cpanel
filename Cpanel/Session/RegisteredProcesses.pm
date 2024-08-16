package Cpanel::Session::RegisteredProcesses;

# cpanel - Cpanel/Session/RegisteredProcesses.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Session::RegisteredProcesses

=head1 SYNOPSIS

    Cpanel::Session::RegisteredProcesses::add_and_save(
        $session_id,
        $session_ref,
        $$,
    );

=head1 DESCRIPTION

This module handles addition of a new process to a session’s list of
registered processes.

=cut

#----------------------------------------------------------------------

use Cpanel::UPIDList ();
use Cpanel::Session  ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 add_and_save( $SESS_ID, $SESS_REF_HR, $PID )

Adds a single $PID to the list of registered processes in $SESS_REF_HR
and saves the data for $SESS_ID.

As part of this, the list of registered processes is checked; any processes
that are no longer active are pruned from that list.

Returns a boolean:

=over

=item B<true>

Returns true when the upid was added to the list

=item B<false>

Returns false when the upid cannot be added to the list (process no longer exists
or is not visible)

=back

This must run as root.

=cut

sub add_and_save {
    my ( $session_id, $session_ref, $pid ) = @_;

    my $reg_obj = Cpanel::UPIDList->new( $session_ref->{'registered_processes'} );

    $reg_obj->prune();

    if ( $reg_obj->add($pid) ) {
        $session_ref->{'registered_processes'} = $reg_obj->serialize();

        Cpanel::Session::saveSession( $session_id, $session_ref );

        return 1;
    }

    return 0;
}

1;
