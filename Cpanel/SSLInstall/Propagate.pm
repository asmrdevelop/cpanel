package Cpanel::SSLInstall::Propagate;

# cpanel - Cpanel/SSLInstall/Propagate.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSLInstall::Propagate

=head1 SYNOPSIS

    Cpanel::SSLInstall::Propagate::install(
        'hal', 'stuff.com',
        $key_pem, @chain_pem,
    );

    Cpanel::SSLInstall::Propagate::delete( 'stuff.com' );

=head1 DESCRIPTION

This module implements propagation logic for SSL installations
and deletions.

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::Worker::WHM ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 install( $USERNAME, $VHOST_NAME, $KEY_PEM, @CHAIN_PEM )

This propagates a single SSL install to the user’s remote worker nodes.

Note that errors in such propagations are B<non-fatal>; they’ll
prompt warnings but won’t trigger exceptions.

Nothing is returned.

B<IMPORTANT:> Don’t use this for propagating multiple SSL installations
at once. For that, use L<Cpanel::SSLInstall::Batch> instead of
this module and L<Cpanel::SSLInstall>.

=cut

sub install ( $username, $vhost_name, $key_pem, @chain_pem ) {    ## no critic qw(ManyArgs) - mis-parse
    local $@;

    my %api_opts = (
        domain => $vhost_name,
        key    => $key_pem,
        crt    => $chain_pem[0],
        cab    => join( "\n", @chain_pem[ 1 .. $#chain_pem ] ),
    );

    _propagate( $username, 'installssl', \%api_opts );

    return;
}

sub _propagate ( $username, $fn, $api_opts_hr ) {
    local $@;

    Cpanel::LinkedNode::Worker::WHM::do_on_all_user_nodes(
        username => $username,

        remote_action => sub ($node_obj) {
            warn if !eval {
                Cpanel::LinkedNode::Worker::WHM::do_whmapi1_call(
                    node_obj => $node_obj,
                    function => $fn,
                    api_opts => $api_opts_hr,
                );

                1;
            };
        },
    );

    return;
}

#----------------------------------------------------------------------

=head2 delete( $USERNAME, $VHOST_NAME )

Like C<install()> but propagates an SSL deletion instead.

=cut

sub delete ( $username, $vhost_name ) {
    _propagate( $username, 'delete_ssl_vhost', { host => $vhost_name } );

    return;
}

1;
