package Whostmgr::Transfers::SystemsBase::LinkedNodes;

# cpanel - Whostmgr/Transfers/SystemsBase/LinkedNodes.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::SystemsBase::LinkedNodes

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

This module provides base logic that multiple linked-node restore
modules use.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();
use Cpanel::Try        ();

use Whostmgr::Transfers::Utils::LinkedNodes ();

use parent qw(
  Whostmgr::Transfers::Systems
);

use constant {
    get_restricted_available => 1,
};

my %cap_parameter_worker_type = reverse %Whostmgr::Transfers::Utils::LinkedNodes::WORKER_TYPE_CAPABILITY_PARAMETER;

#----------------------------------------------------------------------

# These are left undocumented since this module doesn’t really
# envision being subclassed any more than it already is.
sub _restore_distributable    { }
sub _convert_to_distributable { }
sub _dedistribute             { }

=head1 FUNCTIONS

=head2 restricted_restore()

As documented for the account restore framework.

=cut

sub restricted_restore ($self) {
    local $SIG{'__WARN__'} = sub {
        $self->warn(@_);
    };

    for my $param ( sort keys %cap_parameter_worker_type ) {
        my $worker_type = $cap_parameter_worker_type{$param};

        Cpanel::Try::try(
            sub {
                $self->_restore_worker_type($worker_type);
            },
            q<> => sub {
                warn( "Failed to restore $worker_type: " . Cpanel::Exception::get_string($@) );
            },
        );
    }

    return 1;
}

sub _restore_worker_type ( $self, $worker_type ) {
    my $worker_archive_dir = $self->archive_manager()->trusted_archive_contents_dir_for_worker($worker_type);

    my $node_obj = $self->utils()->get_target_worker_node($worker_type);

    if ($node_obj) {
        my $module = "Cpanel::LinkedNode::Convert::ToDistributed::$worker_type";
        Cpanel::LoadModule::load_perl_module($module);

        if ($worker_archive_dir) {

            # Unimplemented for v88: Forgo a re-restoration of an
            # already-restored worker account. This would happen
            # if multiple “workloads” were offloaded to the same
            # worker node.
            if ( $self->{'_alias_restored'}{ $node_obj->alias() } ) {
                die 'unimplemented';
            }
            else {
                $self->_restore_distributable(
                    worker_type        => $worker_type,
                    to_dist_module     => $module,
                    worker_archive_dir => $worker_archive_dir,
                    node_obj           => $node_obj,
                );

                $self->{'_alias_restored'}{ $node_obj->alias() } = 1;
            }
        }
        else {
            $self->_convert_to_distributable(
                worker_type    => $worker_type,
                to_dist_module => $module,
                node_obj       => $node_obj,
            );
        }
    }
    elsif ($worker_archive_dir) {

        # Don’t dedistribute the same archive dir twice.
        if ( !$self->{'_archive_dir_restored'}{$worker_archive_dir} ) {
            $self->_dedistribute(
                worker_type        => $worker_type,
                worker_archive_dir => $worker_archive_dir,
            );

            $self->{'_archive_dir_restored'}{$worker_archive_dir} = 1;
        }
    }

    return;
}

*unrestricted_restore = *restricted_restore;

#----------------------------------------------------------------------

1;
