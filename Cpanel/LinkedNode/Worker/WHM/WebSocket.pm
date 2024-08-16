package Cpanel::LinkedNode::Worker::WHM::WebSocket;

# cpanel - Cpanel/LinkedNode/Worker/WHM/WebSocket.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Worker::WHM::WebSocket

=head1 SYNOPSIS

    Cpanel::LinkedNode::Worker::WHM::WebSocket::connect(
        node_obj => $node_obj,
        module => 'TarRestore',
        query => {
            directory       => $remote_dir,
            setuid_username => 'root',
        },
    )->then( sub ($courier) {

        # Now use $courier to speak WebSocket …
    } );

=head1 DESCRIPTION

This module is a convenience that provides easily-reusable logic to create
a WebSocket connection to any WHM endpoint on a linked node.

This module assumes use of the same event system as
L<Cpanel::Async::WebSocket>.

=cut

#----------------------------------------------------------------------

use Cpanel::Async::WebSocket  ();
use Cpanel::HTTP::QueryString ();
use Cpanel::Services::Ports   ();

use constant REQ_ARGS => ( 'node_obj', 'module', 'query' );

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 promise($courier) = connect( %OPTS )

Asynchronously creates a WebSocket connection to cpsrvd at the appropriate
endpoint on the specified linked node and returns a promise that
resolves when that connection is made.

%OPTS are:

=over

=item * C<node_obj> - a L<Cpanel::LinkedNode::Privileged::Configuration>
instance

=item * C<module> - the name of the cpsrvd WebSocket module (e.g.,
C<TarRestore>)

=item * C<query> - (optional) a hashref of query arguments to pass
in the URL

=back

The returned promise resolves to an instance of
L<Cpanel::Async::WebSocket::Courier>.

=cut

sub connect (%opts) {
    my @missing = grep { !length $opts{$_} } REQ_ARGS();
    die "need: @missing" if @missing;

    my $url = sprintf(
        'wss://%s:%s/websocket/%s',
        $opts{'node_obj'}->hostname() // die("Node object lacks hostname\n"),
        $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
        $opts{'module'},
    );

    if ( %{ $opts{'query'} } ) {
        my $query_str = Cpanel::HTTP::QueryString::make_query_string( $opts{'query'} );

        $url .= "?$query_str" if $query_str;
    }

    return Cpanel::Async::WebSocket::connect(
        $url,
        headers  => [ $opts{'node_obj'}->get_api_token_header() ],
        insecure => $opts{'node_obj'}->allow_bad_tls(),
    );
}

1;
