package Cpanel::LinkedNode::ChildNode;

# cpanel - Cpanel/LinkedNode/ChildNode.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::ParentNode

=head1 SYNOPSIS

    # Throws if the server is already set as a child node.
    Cpanel::LinkedNode::ChildNode::set();

    my $was_set = Cpanel::LinkedNode::ChildNode::unset();

    my $is_set = Cpanel::LinkedNode::ChildNode::is_set();

=head1 DESCRIPTION

This module implements a B<TEMPORARY> solution to inform a child node
of its status as such.

This module assumes that each child node will have exactly 1 parent node.
Thus, it should go away as part of supporting multiple parent nodes per
child node.

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie          ();
use Cpanel::Try              ();
use Cpanel::FileUtils::Write ();

our $_PATH;

BEGIN {
    $_PATH = "/var/cpanel/is_child_node";
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 set()

Sets the local server as a child node. Throws if the server is
already set as such.

=cut

sub set () {
    Cpanel::Try::try(
        sub {
            Cpanel::FileUtils::Write::write( $_PATH, q<> );
        },
        'Cpanel::Exception::ErrnoBase' => sub ($err) {
            if ( $err->error_name() eq 'EEXIST' ) {
                die "This server is already a child node.\n";
            }

            local $@ = $err;
            die;
        },
    );

    return;
}

=head2 $was_set = unset()

Unsets the local server’s child-node status. Returns a boolean
that indicates whether the local server I<was> set as a child node.
(This should not throw except in case of fire.)

=cut

sub unset () {
    return Cpanel::Autodie::unlink_if_exists($_PATH);
}

=head2 is_child_node()

Returns the local server’s child-node status.

=cut

sub is_child_node () {
    return Cpanel::Autodie::exists($_PATH);
}

1;
