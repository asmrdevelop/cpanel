# cpanel - Cpanel/LinkedNode/Worker/WHM/Pkgacct.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::LinkedNode::Worker::WHM::Pkgacct;

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM::Pkgacct

=head1 SYNOPSIS

    my $remote_pkgacct_dir = Cpanel::LinkedNode::Worker::WHM::Pkgacct::execute_pkgacct_for_user( $worker_alias, $username );


=head1 DESCRIPTION

This class contains logic to execute and track a pkgacct session on a remote
worker node.

=cut

use Cpanel::Exception               ();
use Cpanel::JSON                    ();
use Cpanel::LinkedNode              ();
use Cpanel::LinkedNode::Worker::WHM ();

my $poll_state_frequency = 5;
my $poll_state_timeout   = 600;
my $finished_states      = [qw(COMPLETED ABORTED FAILED)];

# TODO: These are currently specific to a Mail worker node. When additional
# node types are defined, we will need to determine the specific options required
# for each node type.
my @pkgacct_skip_options = qw(
  skipacctdb
  skipapitokens
  skipauthnlinks
  skipbwdata
  skipdnssec
  skipdnszones
  skipftpusers
  skiplinkednodes
  skiplogs
  skipresellerconfig
  skipshell
  skipvhosttemplates
);

# Overloadable for testing
sub _poll_state_frequency { return $poll_state_frequency }
sub _poll_state_timeout   { return $poll_state_timeout }
sub _finished_states      { return $finished_states }
sub _sleep                { sleep $poll_state_frequency; return; }
sub _time                 { return time }
sub _pkgacct_skip_options { return \@pkgacct_skip_options }

=head1 FUNCTIONS

=head2 $remote_archive_dir = execute_pkgacct_for_user( $node_alias, $username )

Executes a pkgacct session for the specified user on the worker node corresponding to the
provided alias.

=over

=item INPUT

=over

=item $node_alias

The alias of the remote worker node to perform the pkgacct on.

=item $username

The username of the account to perform pkgacct for.

=back

=item OUTPUT

=over

=item $remote_archive_dir

The path to the pkgacct data on the remote worker node

=back

=back

=cut

sub execute_pkgacct_for_user ( $node_alias, $username ) {

    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( alias => $node_alias );

    my $api_opts = { user => $username, incremental => 1 };
    $api_opts->{$_} = 1 for @{ _pkgacct_skip_options() };

    my $pkgacct = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => 'start_background_pkgacct',
        api_opts => $api_opts,
    );

    my $pkgacct_state = "";
    my $s_time        = _time();
    my $session_id    = $pkgacct->{session_id};

    while ( !grep { $pkgacct_state eq $_ } @{ _finished_states() } ) {

        if ( _time() - $s_time > _poll_state_timeout() ) {
            die Cpanel::Exception->create( "The process timed out while waiting for the remote pkgacct session “[_1]” to finish.", $session_id );
        }

        _sleep();

        my $state = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
            node_obj => $node_obj,
            function => "get_pkgacct_session_state",
            api_opts => {
                session_id => $session_id,
            },
        );

        $pkgacct_state = $state->{state};
    }

    my $log_data = Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
        node_obj => $node_obj,
        function => "fetch_pkgacct_master_log",
        api_opts => { session_id => $session_id },
    );

    my @lines = split /\n/, $log_data->{log};

    if ( $pkgacct_state eq "FAILED" ) {

        my $last_line = eval { Cpanel::JSON::Load( $lines[-1] ) };

        if ( !$last_line || !$last_line->{contents} ) {
            die Cpanel::Exception->create_raw("Failed to determine pkgacct error from log");
        }
        else {
            die Cpanel::Exception->create_raw( $last_line->{contents} );
        }

    }

    my $working_dir;

    # To identify the working directory for the pkgacct run, we have to examine the log file
    # for a line where the contents looks like "pkgacct working dir : /home/cpmove-username"
    # and extract the directory name.
    foreach my $line (@lines) {

        # We can throw away any parse errors since all we care about is whether or not we
        # can get the working directory from the output contents. If none of the lines is
        # valid JSON or no working directory is found, the function will die anyway.
        my $json = eval { Cpanel::JSON::Load($line) };
        if ( $json && $json->{type} && $json->{type} eq 'out' && $json->{contents} && index( $json->{contents}, "working dir" ) != -1 ) {
            ( undef, $working_dir ) = split /\s+:\s+/, $json->{contents}, 2;
            last;
        }
    }

    die "Could not identify pkgacct working directory" if !$working_dir;

    return $working_dir;
}

1;
