package Cpanel::DKIM::Propagate::Send;

# cpanel - Cpanel/DKIM/Propagate/Send.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DKIM::Propagate::Send

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode             ();
use Whostmgr::API::1::Utils::Batch ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 dkim_keys_to_remote( $ALIAS, \%DOMAIN_KEY )

This function complements L<Cpanel::DKIM::Propagate::Data>’s
C<process_propagations()> to implement the actual sending of the DKIM
key API calls.

$ALIAS is the remote Mail worker’s linked-node alias.
%DOMAIN_KEY is a hash of domain name to either:

=over

=item * a PEM representation of the DKIM key to send

=item * undef, to indicate that the domain’s DKIM should be deleted

=back

The full set of changes is sent as a single WHM API v1 batch call.
If that API call fails, an exception is thrown.

Nothing is returned.

=cut

sub dkim_keys_to_remote ( $alias, $domain_key_hr ) {

    my $node_obj = Cpanel::LinkedNode::get_linked_server_node( alias => $alias );

    # If the node linkage is not defined, then we just want to
    # delete the pending DKIM propagations for that mail node.
    return if !$node_obj;

    my ( $whm_username, $whm_token ) = map { $node_obj->$_() } qw( username api_token );

    my ( @add_domains, @del_domains, @add_keys );

    for my $domain ( keys %$domain_key_hr ) {
        if ( my $key = $domain_key_hr->{$domain} ) {
            push @add_domains, $domain;
            push @add_keys,    $key;
        }
        else {
            push @del_domains, $domain;
        }
    }

    my %add_args = ( domain => \@add_domains, key => \@add_keys );

    my @batch;

    if (@add_domains) {
        push @batch, [ install_dkim_private_keys => \%add_args ];
    }

    if (@del_domains) {
        push @batch, [ disable_dkim => { domain => \@del_domains } ];
    }

    my $batch_hr = Whostmgr::API::1::Utils::Batch::assemble_batch(@batch);

    my $api = $node_obj->get_remote_api();

    my $result = $api->request_whmapi1( batch => $batch_hr );

    if ( my $err = $result->get_error() ) {
        die "Remote DKIM synchronization failed: $err";
    }

    return;
}

1;
