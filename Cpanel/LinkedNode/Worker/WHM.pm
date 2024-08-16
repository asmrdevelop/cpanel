package Cpanel::LinkedNode::Worker::WHM;

# cpanel - Cpanel/LinkedNode/Worker/WHM.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::APICommon::Persona      ();    ## PPI NO PARSE - mis-parse
use Cpanel::LinkedNode::Index::Read ();

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM - Basic methods for implementing WHM linked node logic

=head1 SYNOPSIS

    use Cpanel::LinkedNode::Worker::WHM ();

    sub add_a_package($pkgname) {

        # Define a routine to perform an action on the remote nodes (ex: addpkg)
        my $remote_action_cr = sub($node_obj) {
            my $api_obj = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);

            Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                node_obj => $node_obj,
                api_obj  => $api_obj,
                function => 'addpkg', # The WHM API function to perform an action
                api_opts => { name => $pkgname }        # The options needed by the API function
            );

            return;
        };

        # Optionally, define a routine to undo the action on the remote nodes (ex: killpkg)
        my $remote_undo_cr = sub($node_obj) {
            my $api_obj = Cpanel::LinkedNode::Worker::WHM::create_node_api_obj($node_obj);

            Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                node_obj => $node_obj,
                api_obj  => $api_obj,
                function => 'killpkg', # The WHM API function to perform an action
                api_opts => { name => $pkgname }        # The options needed by the API function
            );

            return;
        };

        # Optionally, define a routine to perform a local action when the remote action succeeds on all nodes
        # The return value of the local action will be returned by do_on_all_nodes
        my $local_action_cr = sub {
            return Whostmgr::Packages::Mod::_addpkg({ name => $pkgname });
        };

        # Optionally, define a routine to undo the local action (ex: killpkg)
        my $local_undo_cr = sub {
            return Whostmgr::Packages::__kilpkg({ pkgname => $pkgname });
        }


        # Execute the remote action on all nodes, and then execute the local action
        return Cpanel::LinkedNode::Worker::WHM::do_on_all_nodes(
            local_action  => $local_action,
            remote_action => $remote_action,
            remote_undo   => $remote_undo,
        );

    }

    1;

=head1 DESCRIPTION

This module is a base class for defining logic to execute operations on linked server nodes.

It provides convenience methods for making WHMAPI1 and UAPI calls using a
C<Cpanel::LinkedNode::Privileged::Configuration> object, as well as executing
operations across all linked server nodes and undoing them in the event of a
failure.

=head1 METHODS

=head2 do_on_all_nodes( local_action => $local_action_cr, local_undo => $local_undo_cr, remote_action => $remote_action_cr, remote_undo => $remote_undo_cr )

Executes an action on all linked server nodes, rolling back all nodes if a
failure occurs.

=over

=item Input

=over

=item C<CODEREF> - remote_action

The action to perform on the remote server. Receives a
L<Cpanel::LinkedNode::Privileged::Configuration> instance that refers
to the remote server.

=item C<CODEREF> - remote_undo

The action to undo the changes made by C<remote_action> in the event of a
failure. Receives the same L<Cpanel::LinkedNode::Privileged::Configuration>
instance as C<remote_action>.

=item C<CODEREF> - local_action (optional)

The action to perform on the local server

=item C<CODEREF> - local_undo (optional)

The action to undo the changes made by C<local_action> in the event of a failure

=back

=item Output

=over

Returns the result of the local action if specified, or an empty list

=back

=back

=cut

sub do_on_all_nodes (%opts) {

    my ( $local_action, $local_undo, $remote_action, $remote_undo ) = @opts{qw(local_action local_undo remote_action remote_undo)};

    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    if ( scalar keys %$nodes_hr == 0 ) {
        return $local_action ? $local_action->() : ();
    }

    require Cpanel::CommandQueue;
    my $cq = Cpanel::CommandQueue->new();

    my @return;

    if ( $local_action || $local_undo ) {
        $cq->add(
            sub { @return = $local_action->() if $local_action },
            sub { $local_undo->() if $local_undo },
            "local",
        );
    }

    # Sort on alias so the node actions happen in a predictable order
    foreach my $alias ( sort keys %$nodes_hr ) {
        $cq->add(
            sub { $remote_action->( $nodes_hr->{$alias} ) },
            sub { $remote_undo->( $nodes_hr->{$alias} ) if $remote_undo },
            $alias
        );
    }

    $cq->run();

    return @return;
}

# Cpanel::LinkedNode::Worker::WHM

=head2 do_on_nodes ( %opts )

Like C<do_on_all_nodes()> but only runs the remote callbacks on
remotes whose alias is specified.

It takes one additional parameter:

=over

=item * C<aliases> - An ARRAYREF of node aliases.

=back

=cut

sub do_on_nodes (%opts) {

    my $aliases_ar = delete $opts{aliases} or die "need aliases";

    _validate_aliases($aliases_ar);

    my %skipped;

    my @args = (
        %opts{ 'local_action', 'local_undo' },

        remote_action => sub ($node_obj) {
            my $node_alias = $node_obj->alias();

            # Skip any nodes that aren’t specified:
            if ( !grep { $_ eq $node_alias } @$aliases_ar ) {
                $skipped{$node_alias} = 1;
                return;
            }

            return $opts{'remote_action'}->($node_obj);
        },
    );

    if ( my $remote_undo = $opts{'remote_undo'} ) {
        push @args, remote_undo => sub ($node_obj) {
            my $node_alias = $node_obj->alias();

            return if $skipped{$node_alias};

            return $remote_undo->($node_obj);
        };
    }

    return do_on_all_nodes(@args);

}

#----------------------------------------------------------------------

=head2 do_on_all_user_nodes( %opts )

Like C<do_on_all_nodes()> but only runs the remote callbacks on
remotes that an indicated user uses.

It takes one additional parameter:

=over

=item * C<username> - The name of the user.

=back

=cut

sub do_on_all_user_nodes (%opts) {
    my $username = delete $opts{'username'} or die 'need username';

    require Cpanel::Config::LoadCpUserFile;
    my $cpuser_data = Cpanel::Config::LoadCpUserFile::load_or_die($username);

    require Cpanel::LinkedNode::Worker::GetAll;
    my @worker_hashrefs = Cpanel::LinkedNode::Worker::GetAll::get_aliases_and_tokens_from_cpuser($cpuser_data);

    my @aliases = map { $_->{alias} } @worker_hashrefs;

    return do_on_nodes( %opts, aliases => \@aliases );
}

#----------------------------------------------------------------------

=head2 create_node_api_obj($node_obj)

Creates a C<Cpanel::RemoteAPI::WHM> object for the specified remote node

=over

=item Input

=over

=item C<SCALAR>

The C<Cpanel::LinkedNode::Privileged::Configuration> object to create the API object for

=back

=item Output

=over

Returns the C<Cpanel::RemoteAPI::WHM> object created using the node configuration

=back

=back

=cut

sub create_node_api_obj ($node_obj) {
    return $node_obj->get_remote_api();
}

=head2 do_whmapi1_call( node_obj => $node_obj, api_obj => $api_obj, function => "function_to_call", api_opts => { } )

Calls the specified WHM API1 function with the provided options

=over

=item Input

=over

=item C<SCALAR> - node_obj

A C<Cpanel::LinkedNode::Privileged::Configuration> object

=item C<SCALAR> - api_obj (optional)

A L<Cpanel::RemoteAPI::WHM> object. If not given, the result of
C<node_obj>’s C<get_remote_api()> method will be used.

=item C<SCALAR> - function

The WHM API1 function to call

=item C<HASHREF> - api_opts

The options to pass to the WHM API1 function

=back

=item Output

=over

Returns the data portion of the API result on success, dies otherwise

=back

=back

=cut

sub do_whmapi1_call (%opts) {

    my ( $node_obj, $api_obj, $function, $api_opts ) = @opts{qw(node_obj api_obj function api_opts)};

    $api_obj ||= $node_obj->get_remote_api();

    $api_opts ||= {};
    local $api_opts->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    my $resp = $api_obj->request_whmapi1_or_die( $function, $api_opts );

    return $resp->get_data();
}

=head2 do_raw_whmapi1_call( node_obj => $node_obj, api_obj => $api_obj, function => "function_to_call", api_opts => { } )

Like C<do_whmapi1_call> except it does not die on error and returns the entire response
object instead of just the data portion of the response.

=cut

sub do_raw_whmapi1_call (%opts) {

    my ( $node_obj, $api_obj, $function, $api_opts ) = @opts{qw(node_obj api_obj function api_opts)};

    $api_obj ||= $node_obj->get_remote_api();

    $api_opts ||= {};
    local $api_opts->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    return $api_obj->request_whmapi1( $function, $api_opts );
}

=head2 do_uapi_call_as_user( node_obj => $node_obj, api_obj => $api_obj, username => $username, module => $module, function => $function, api_opts => {} )

Calls the specified UAPI function with the provided options as the specified user

=over

=item Input

=over

=item C<SCALAR> - node_obj

A C<Cpanel::LinkedNode::Privileged::Configuration> object

=item C<SCALAR> - api_obj

A C<Cpanel::RemoteAPI::WHM> object

=item C<SCALAR> - username

A string specifying the username to make the UAPI call as

=item C<SCALAR> - module

The UAPI module to call

=item C<SCALAR> - function

The UAPI function to call

=item C<HASHREF> - api_opts

The options to pass to the WHM API1 function

=back

=item Output

=over

Returns the data portion of the API result on success, dies otherwise

=back

=back

=cut

sub do_uapi_call_as_user (%opts) {

    my ( $node_obj, $api_obj, $cpusername, $module, $function, $api_opts ) = @opts{qw(node_obj api_obj username module function api_opts)};

    $api_obj ||= $node_obj->get_remote_api();

    $api_opts ||= {};
    local $api_opts->{'api.persona'} = Cpanel::APICommon::Persona::PARENT;

    my $resp = $api_obj->request_cpanel_uapi_or_die( $cpusername, $module, $function, $api_opts );

    return $resp->data();
}

#----------------------------------------------------------------------

sub _validate_aliases ($aliases_ar) {
    my @server_aliases;

    do_on_all_nodes(
        remote_action => sub ($node_obj) {
            push @server_aliases, $node_obj->alias();
        }
    );

    local ( $@, $! );
    require Cpanel::Set;

    my @bad = Cpanel::Set::difference( $aliases_ar, \@server_aliases );

    if (@bad) {
        die "Bad alias(es): @bad";
    }

    return;
}

1;
