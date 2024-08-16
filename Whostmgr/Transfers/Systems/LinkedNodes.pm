package Whostmgr::Transfers::Systems::LinkedNodes;

# cpanel - Whostmgr/Transfers/Systems/LinkedNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::LinkedNodes

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module exists to be called from the account restore system.
It should not be invoked directly except from that framework.

This module handles the following cases:

=over

=item * Account archive lacks a subarchive for the distributable
(e.g., C<Mail>), and the distributable is to be on a linked node.

=item * Account archive contains a subarchive for the distributable
(e.g., C<Mail>), but the distributable is to be local.

=back

See L<Whostmgr::Transfers::Systems::LinkedNodesSubarchives>
for how the other case (subarchive to linked node) is handled.

=head1 METHODS

=cut

use Cpanel::Imports;

use Cpanel::Autodie    ();
use Cpanel::LoadModule ();

use parent qw(
  Whostmgr::Transfers::SystemsBase::LinkedNodes
);

use constant {
    get_phase => 100,
};

=head2 I<OBJ>->get_prereq()

Standard method; see base class.

=cut

sub get_prereq {
    return ['PostRestoreActions'];
}

=head2 I<OBJ>->get_summary()

POD for cplint. Don’t call this directly.

=cut

sub get_summary {
    my ($self) = @_;
    return [ locale()->maketext('This module handles the linked node setup.') ];
}

sub _convert_to_distributable ( $self, %opts ) {
    $self->out( locale()->maketext( 'Offloading “[_1]” functionality to “[_2]” ([_3]) …', $opts{'worker_type'}, $opts{'node_obj'}->hostname(), $opts{'node_obj'}->alias() ) );

    $opts{'to_dist_module'}->can('convert')->(
        username     => $self->newuser(),
        worker_alias => $opts{'node_obj'}->alias(),
        output_obj   => $self->utils()->logger(),
    );

    return;
}

sub _dedistribute ( $self, %opts ) {
    my ( $worker_type, $worker_archive_dir ) = @opts{ 'worker_type', 'worker_archive_dir' };

    $self->out( locale()->maketext( 'Restoring “[_1]” data from the child node archive …', $worker_type ) );

    my $homedir_path = "$worker_archive_dir/homedir";

    Cpanel::Autodie::lstat($homedir_path);
    if ( -l _ ) {
        my $dest = readlink($homedir_path);
        die "Refuse to extract from symlink “$homedir_path” ($dest)!";
    }

    my $newuser = $self->utils()->local_username();

    my ( $uid, $gid, $user_homedir ) = ( $self->utils()->pwnam() )[ 2, 3, 7 ];
    require Cpanel::PwCache::Group;
    my @supplemental_gids = Cpanel::PwCache::Group::get_supplemental_gids_for_user($newuser);

    my $constants_module = "Cpanel::LinkedNode::Convert::$worker_type\::Constants";
    Cpanel::LoadModule::load_perl_module($constants_module);

    my @include = grep {

        # Preemptive safety in case we ever add any deep paths
        # to HOMEDIR_PATHS.
        die "Need deep-no-follow check!" if tr</><>;

        Cpanel::Autodie::exists_nofollow("$homedir_path/$_");
    } $constants_module->HOMEDIR_PATHS();

    require Cpanel::SafeSync::UserDir;
    Cpanel::SafeSync::UserDir::sync_to_userdir(
        source  => $homedir_path,
        target  => $user_homedir,
        setuid  => [ $uid, $gid, @supplemental_gids ],
        include => \@include,
    );

    return;
}

#----------------------------------------------------------------------

1;
