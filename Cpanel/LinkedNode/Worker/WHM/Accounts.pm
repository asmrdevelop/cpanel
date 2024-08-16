package Cpanel::LinkedNode::Worker::WHM::Accounts;

# cpanel - Cpanel/LinkedNode/Worker/WHM/Accounts.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::LinkedNode::Worker::WHM ();

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM::Packages - Methods for managing accounts across linked nodes

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Worker::WHM::Accounts ();

    Cpanel::LinkedNode::Worker::WHM::Packages->create_account_and_token_on_node( $api_opts, $node_obj );

=head1 DESCRIPTION

This module provides methods for managing accounts across linked server nodes. The methods
will execute API methods on the linked nodes to create, modify, or terminate an account.
If any of the remote API calls fail the methods will rollback the changes so the accounts
are in their preexisting state.

=head1 METHODS

=head2 Whostmgr::LinkedNode::Worker::WHM::Accounts::create_account_and_token_on_node( $api_opts, $node_obj )

Creates a cPanel account and a cPanel level API token for that account on the specified node.

This method calls the C<createacct> WHM API 1 method on the remote node to create the account
and the C<Tokens::create_full_access> UAPI method as the new user to create an API token for
the user.

If the C<create_full_access> UAPI method fails, then the C<killacct> WHM API 1 method is
called on the remote node to terminate the newly created account.

=over

=item Input

=over

=item C<HASHREF> - API options

A C<HASHREF> of API options to pass to the WHM C<createacct> method. See the documentation for
that WHM API 1 method to see suitable key/value pairs.

=item C<Cpanel::LinkedNode::Privileged::Configuration> - Remote node

The privileged configuration object for the remote node to create the account on.

=back

=item Output

=over

=item C<SCALAR> - String - API Token

Returns the API token for the new user on success, dies otherwise.

=back

=back

=cut

sub create_account_and_token_on_node ( $api_opts, $node_obj ) {

    require Cpanel::CommandQueue;
    my $cq = Cpanel::CommandQueue->new();

    my $api_obj   = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);
    my $username  = $api_opts->{username} || $api_opts->{user};
    my %base_opts = ( node_obj => $node_obj, api_obj => $api_obj );

    if ( !$username ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw( "You must specify either the “[_1]” or “[_2]” parameter.", [ "username", "user" ] );
    }

    my $api_token;

    my %child_api_opts = (
        %$api_opts,

        # Child accounts can’t currently have any of the following:
        hasshell => 0,
        cgi      => 0,
        reseller => 0,
    );

    # Child accounts are always root-owned.
    delete $child_api_opts{'owner'};

    $cq->add(
        sub { Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => "PRIVATE_createacct_child", api_opts => \%child_api_opts ); },
        sub { Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call( %base_opts, function => "removeacct",               api_opts => { user => $username } ); },
    );

    $cq->add(
        sub {

            my $data = Cpanel::LinkedNode::Worker::WHM::do_uapi_call_as_user(
                node_obj => $node_obj,
                api_obj  => $api_obj,
                username => $username,
                module   => "Tokens",
                function => "create_full_access",
                api_opts => { name => "MailNodeLinkage" }
            );

            $api_token = $data->{token};
        }
    );    # No undo action required for API token since if it fails we die and the removeacct undo above would remove it anyway

    $cq->run();

    return $api_token;
}

=head2 Whostmgr::LinkedNode::Worker::WHM::Accounts::change_account_package( $username, $package_name )

Changes the package for the specified user on all of the worker nodes the user is linked to and
on the local server.

This method calls the C<changepackage> WHM API 1 method on each of the user’s the worker nodes
and the C<Whostmgr::Accounts::Upgrade::upacct> method on the local server.

If any of the nodes or the local server fail the package change, the user’s package is reverted
to whatever it was before.

=over

=item Input

=over

=item C<SCALAR> - String - Username

The username of the user to change the package for.

=item C<SCALAR> - String - Package Name

The name of the package to apply to the user.

=back

=item Output

This function returns the output from the local C<Whostmgr::Accounts::Upgrade::upacct> call on
success, dies otherwise.

=back

=cut

sub change_account_package ( $username, $new_package ) {

    require Whostmgr::Accounts::Upgrade;
    require Cpanel::Config::LoadCpUserFile;

    my $cpuser_ref      = Cpanel::Config::LoadCpUserFile::loadcpuserfile($username);
    my $current_package = $cpuser_ref->{'PLAN'} || 'default';

    my $local_action = sub {
        return _change_package_or_die( $username, $new_package );
    };

    my $local_undo = sub {
        return _change_package_or_die( $username, $current_package );
    };

    my $remote_action = sub ($node_obj) {

        Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
            node_obj => $node_obj,
            function => 'changepackage',
            api_opts => { user => $username, pkg => $new_package },
        );

        return;
    };

    my $remote_undo = sub ($node_obj) {

        Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
            node_obj => $node_obj,
            function => 'changepackage',
            api_opts => { user => $username, pkg => $current_package },
        );

        return;
    };

    return Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username      => $username,
        local_action  => $local_action,
        local_undo    => $local_undo,
        remote_action => $remote_action,
        remote_undo   => $remote_undo,
    );

}

sub _change_package_or_die ( $username, $package ) {

    my ( $status, $msg, @extended ) = Whostmgr::Accounts::Upgrade::upacct( user => $username, pkg => $package );

    if ( !$status ) {
        require Cpanel::Exception;
        die Cpanel::Exception->create_raw($msg);
    }

    return ( $status, $msg, @extended );
}

1;
