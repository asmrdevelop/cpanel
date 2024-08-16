package Cpanel::LinkedNode::CheckTLS;

# cpanel - Cpanel/LinkedNode/CheckTLS.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::CheckTLS

=head1 DESCRIPTION

This module encapsulates logic to check a linked node’s TLS status.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception               ();
use Cpanel::LinkedNode::Index::Read ();
use Cpanel::SSL::RemoteFetcher      ();
use Cpanel::Services::Ports         ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $node_status_hr = verify_linked_nodes_whm()

Reports the TLS status of all of a server’s linked nodes.

The return is a reference to a hash whose keys are the node aliases
and whose values are L<AnyEvent>-backed promises (i.e., L<Promise::ES6>
instances). Each promise resolves to either:

=over

=item On failure, undef. (A C<warn()>ing is thrown that indicates the
failure.)

=item On success, a hash reference:

=over

=item * C<hostname> - The node’s hostname, as stored in the linkage.

=item * C<chain> - As from L<Cpanel::SSL::RemoteFetcher>.

=item * C<handshake_verify> - As from L<Cpanel::SSL::RemoteFetcher>.

=back

=back

=cut

sub verify_linked_nodes_whm() {
    my $port = $Cpanel::Services::Ports::SERVICE{'whostmgrs'};

    my $nodes_hr = Cpanel::LinkedNode::Index::Read::get();

    my $fetcher = Cpanel::SSL::RemoteFetcher->new();

    my %alias_return;

    for my $alias ( keys %$nodes_hr ) {
        my $hostname = $nodes_hr->{$alias}{'hostname'};

        $alias_return{$alias} = $fetcher->fetch( $hostname => $port )->then(
            sub ($result_hr) {
                my $leaf = $result_hr->{'chain'}->[0];

                return {
                    hostname => $hostname,
                    %{$result_hr}{ 'chain', 'handshake_verify' },
                };
            },
        )->catch(
            sub ($err) {
                warn Cpanel::Exception::get_string($err);
                return undef;
            },
        );
    }

    return \%alias_return;
}

1;
