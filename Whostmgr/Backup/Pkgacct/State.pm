# cpanel - Whostmgr/Backup/Pkgacct/State.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Whostmgr::Backup::Pkgacct::State;

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Backup::Pkgacct::State

=head1 SYNOPSIS

    my $state = Whostmgr::Backup::Pkgacct::State::get_pkgacct_session_state( $pkgacct_session_id );

=head1 DESCRIPTION

This module encapsulates logic to determine the state of a background
pkgacct session. It is only valid for pkgacct sessions that were spawned
in the background via the C<Whostmgr::API::1::Backup::start_background_pkgacct>
method.

=cut

use Try::Tiny;

use Cpanel::Autodie ();
use Cpanel::JSON    ();

use constant {
    RUNNING   => "RUNNING",
    FAILED    => "FAILED",
    COMPLETED => "COMPLETED",
};

=head1 FUNCTIONS

=head2 my $state = Whostmgr::Backup::Pkgacct::State::get_pkgacct_session_state( $pkgacct_session_id )

=over

=item INPUT

=over

=item $pkgacct_session_id

The id of a background pkgacct session returned from the
C<Whostmgr::API::1::Backup::start_background_pkgacct> method

=back

=item OUTPUT

=over

=item $pkgacct_session_state

This function returns a string indicating the state of the
background pkgacct session. One of:

=over

=item RUNNING

Indicates that the background pkgacct session is still running

=item FAILED

Indicates that the background pkgacct session terminated with an error

=item COMPLETED

Indicates that the background pkgacct session completed successfully

=back

=back

=back

=cut

sub get_pkgacct_session_state ($session_id) {

    require Whostmgr::Backup::Pkgacct::Config;
    my $upid_file = $Whostmgr::Backup::Pkgacct::Config::SESSION_DIR . "/$session_id/upid";

    my $upid = Cpanel::Autodie::readlink_if_exists($upid_file);

    # It’s possible something catastrophic happened and the upid file exists but
    # the process has terminated, double check that the upid is still alive.
    require Cpanel::UPID;
    return RUNNING if $upid && Cpanel::UPID::is_alive($upid);

    require Whostmgr::Backup::Pkgacct::Logs;

    my $log_output = Whostmgr::Backup::Pkgacct::Logs::fetch_master_log($session_id);

    my @lines = split /\n/, $log_output;

    my $last_json = eval { Cpanel::JSON::Load( $lines[-1] ) };
    die "Could not identify state from pkgacct log" if !$last_json || !$last_json->{type} || !$last_json->{contents};

    # If the process is no longer running and the last message was an error, pkgacct terminated with a failure
    return FAILED if $last_json->{type} eq 'error';

    # If the process is no longer running and the last message has the completion, pkgacct completed successfully
    return COMPLETED if index( $last_json->{contents}, "pkgacct completed" ) != -1;

    die "Could not identify state from pkgacct log";
}

1;
