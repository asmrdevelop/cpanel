package Whostmgr::Transfers::SystemsBase::Distributable;

# cpanel - Whostmgr/Transfers/SystemsBase/Distributable.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::SystemsBase::Distributable

=head1 DESCRIPTION

This subclass of L<Whostmgr::Transfers::Systems> overrides the C<extractdir()>
method to provide the appropriate directory for a given distributable
workload’s status in the archive as well as the arguments given to the
account restore.

For example, if the account has a Mail subarchive, and a given restore module
subclasses a Mail-centric subclass of this class (see below), and the restore
indicates not to have the restored user use a Mail worker, then C<extractdir()>
will return the subarchive’s base directory rather than the main archive’s base
directory.

=head1 SUBCLASS INTERFACE

Restore modules should not be directly subclass this interface; instead,
create a subclass for the particular distributable workload (e.g., C<Mail>)
that pertains to the account functionality that the restore module handles.
For example, modules for mail should subclass
L<Whostmgr::Transfers::SystemsBase::Distributable::Mail>.

To create a new distributable-workload subclass, give it a C<_WORKER_TYPE>
constant that identifies the relevant worker type (e.g., C<Mail>).

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::Systems';

sub get_prereq {
    return ['LinkedNodesSubarchives'];
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<OBJ>->extractdir()

Provides the override described above.

=cut

sub extractdir ($self) {
    my $target_node = $self->utils()->get_target_worker_node( $self->_WORKER_TYPE() );

    my $dir;

    # The archive can store a distributed account or a non-distributed.
    # We can restore the account as distributed or non-distributed.
    # Thus, four (2**2) possibilities exist:
    #
    # 1) Archive distributed, new account distributed.
    #   In this case, we want the main archive to be restored here
    #   (on the controller) since we’ll restore the worker account
    #   separately.
    #
    # 2) Archive non-distributed, new account distributed.
    #   We restore as though to a non-distributed account, then convert.
    #   This workflow is a suboptimal but conservative first implementation.
    #
    # 3) Archive distributed, new account non-distributed.
    #   In this case—and ONLY in this case—we restore from the worker
    #   archive since the newly-restored account needs the worker
    #   archive’s data.
    #
    # 4) Archive non-distributed, new account non-distributed.
    #   The “classic”, simple case.
    #
    if ( !$target_node ) {
        $dir = $self->archive_manager()->trusted_archive_contents_dir_for_worker( $self->_WORKER_TYPE() );
    }

    # If there’s no stored worker archive, or if we’re re-distributing
    # the archived account, then we return the main archive dir.
    $dir ||= $self->archive_manager()->trusted_archive_contents_dir();

    return $dir;
}

1;
