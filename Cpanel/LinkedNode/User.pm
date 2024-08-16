package Cpanel::LinkedNode::User;

# cpanel - Cpanel/LinkedNode/User.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::User

=head1 SYNOPSIS

    my $config_hr = get_node_configuration( $NODE_ALIAS );

=head1 DESCRIPTION

This module contains logic that unprivileged users can use to look up
aspects of worker node configuration that are relevant to them.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Cpanel::Autodie ( 'readlink', 'readlink_if_exists' );
use Cpanel::LinkedNode::Alias ();

# mocked in tests
our $_LINKED_NODES_USER_DIR       = '/var/cpanel/linked_nodes_user';
our $_LINKED_NODES_USER_ALIAS_DIR = "$_LINKED_NODES_USER_DIR/alias";

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $config_obj = get_node_configuration( $NODE_ALIAS )

Returns a L<Cpanel::LinkedNode::User::Configuration> instance.

This throws an exception if the given $NODE_ALIAS does not refer to a
configured worker node.

=cut

sub get_node_configuration ($node_alias) {
    return _get_node_configuration( $node_alias, 'readlink' );
}

sub get_node_configuration_if_exists ($node_alias) {
    return _get_node_configuration( $node_alias, 'readlink_if_exists' );
}

sub _get_node_configuration ( $node_alias, $readlink_fn ) {

    Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($node_alias);

    my $link_path = "$_LINKED_NODES_USER_ALIAS_DIR/$node_alias";

    my $link_value = Cpanel::Autodie->can($readlink_fn)->($link_path);

    return $link_value && do {
        my ( $hostname, $tls_verified ) = split( /\//, $link_value, 2 );

        require Cpanel::LinkedNode::User::Configuration;
        Cpanel::LinkedNode::User::Configuration->new(
            allow_bad_tls => !$tls_verified,
            hostname      => $hostname,
        );
    };
}

sub sync_node_aliases {

    my ( $nodes_hr, $deleted_alias ) = @_;

    foreach my $alias ( keys %$nodes_hr ) {
        sync_node_alias( $alias, $nodes_hr->{$alias}{hostname}, $nodes_hr->{$alias}{tls_verified} );
    }

    if ($deleted_alias) {
        Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($deleted_alias);
        _delete_node_alias($deleted_alias);
    }

    return;
}

sub sync_node_alias {

    my ( $alias, $hostname, $tls_verified ) = @_;

    Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($alias);

    Cpanel::Autodie::mkdir_if_not_exists( $_LINKED_NODES_USER_DIR,       0711 );
    Cpanel::Autodie::mkdir_if_not_exists( $_LINKED_NODES_USER_ALIAS_DIR, 0711 );

    my $link_data = sprintf( "%s/%s", $hostname, $tls_verified ? 1 : 0 );
    my $link_path = "$_LINKED_NODES_USER_ALIAS_DIR/$alias";

    my $temp_path = "$_LINKED_NODES_USER_ALIAS_DIR/.tmp.$alias.$$" . substr( rand(), 1 );
    Cpanel::Autodie::symlink( $link_data, $temp_path );

    try {
        Cpanel::Autodie::rename( $temp_path, $link_path );
    }
    catch {
        warn if !eval { Cpanel::Autodie::unlink_if_exists($temp_path); 1 };

        die $_;
    };

    return;
}

sub _delete_node_alias {
    my ($alias) = @_;
    Cpanel::Autodie::unlink_if_exists("$_LINKED_NODES_USER_ALIAS_DIR/$alias");
    return;
}

1;
