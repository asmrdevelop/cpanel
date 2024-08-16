package Cpanel::LinkedNode::Worker::Utils;

# cpanel - Cpanel/LinkedNode/Worker/Utils.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::Utils

=head1 SYNOPSIS

    my $path = Cpanel::LinkedNode::Worker::Utils::get_remote_homedir(
        $node_obj,  # Cpanel::LinkedNode::Privileged::Configuration
        'steve',
    );

=head1 DESCRIPTION

This module contains pieces of reusable functionality for workers.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Worker::WHM ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $path = get_remote_homedir( $NODE_OBJ, $USERNAME )

Returns the absolute path to $USERNAME’s home directory on the node
that $NODE_OBJ (a L<Cpanel::LinkedNode::Privileged::Configuration> instance)
represents.

=cut

sub get_remote_homedir ( $node_obj, $username ) {

    my $data_hr = Cpanel::LinkedNode::Worker::WHM::do_uapi_call_as_user(
        username => $username,
        node_obj => $node_obj,
        module   => 'Variables',
        function => 'get_user_information',
        api_opts => { name => 'home' },
    );

    return $data_hr->{'home'} || die "Failed to find “$username”’s remote homedir!";
}

1;
