package Whostmgr::Transfers::Systems::LinkedNodesSubarchives;

# cpanel - Whostmgr/Transfers/Systems/LinkedNodesSubarchives.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::LinkedNodesSubarchives

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

It restores the user’s linked-node configuration for distributables
(e.g., C<Mail>) where the configuration is stored via a subarchive in the
account archive. If any of the remote restores fail, then we fall back
to local restore for the given distributable.

See L<Whostmgr::Transfers::Systems::LinkedNodes> for logic that
handles other related cases.

=head1 METHODS

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Try ();

use parent qw(
  Whostmgr::Transfers::SystemsBase::LinkedNodes
);

#----------------------------------------------------------------------

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary {
    return [ locale()->maketext('This module restores linked-node configurations when the archive contains linked node data.') ];
}

sub _restore_distributable ( $self, %opts ) {
    $self->out( locale()->maketext( 'Restoring “[_1]” functionality to “[_2]” ([_3]) …', $opts{'worker_type'}, $opts{'node_obj'}->hostname(), $opts{'node_obj'}->alias() ) );

    my $ok;

    Cpanel::Try::try(
        sub {
            $opts{'to_dist_module'}->can('restore')->(
                username     => $self->newuser(),
                worker_alias => $opts{'node_obj'}->alias(),
                output_obj   => $self->utils()->logger(),
                cpmove_path  => $opts{'worker_archive_dir'},
            );

            $ok = 1;
        },
        q<> => sub {
            my $err = $@;

            $self->utils()->cancel_target_worker_node( $opts{'worker_type'} );

            $self->utils()->add_skipped_item( locale()->maketext( 'The system failed to restore “[_1]” functionality to “[_2]” ([_3]). Because of this, the restored “[_1]” functionality will reside on the local server.', $opts{'worker_type'}, $opts{'node_obj'}->hostname(), $opts{'node_obj'}->alias() ) );

            local $@ = $err;
            die;
        },
    );

    return;
}

#----------------------------------------------------------------------

1;
