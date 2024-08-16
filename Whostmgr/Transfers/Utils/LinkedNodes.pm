package Whostmgr::Transfers::Utils::LinkedNodes;

# cpanel - Whostmgr/Transfers/Utils/LinkedNodes.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Utils::LinkedNodes

=head1 SYNOPSIS

    my @skips = Whostmgr::Transfers::Utils::LinkedNodes::validate_stored_linked_nodes( '/extract/dir', \%CPUSER );

=head1 DESCRIPTION

This module contains logic to validate an account archive’s stored
linked-node configuration.

=cut

#----------------------------------------------------------------------

use Cpanel::Imports;

use Cpanel::LinkedNode::Alias                  ();
use Cpanel::LinkedNode::Alias::Constants       ();    # PPI USE OK - Constants
use Cpanel::LinkedNode::User                   ();
use Whostmgr::Transfers::Utils::WorkerNodesObj ();

#----------------------------------------------------------------------

=head1 GLOBAL VARIABLES

=head2 %WORKER_TYPE_CAPABILITY_PARAMETER

Matches input outputs for worker capabilities with the actual worker type.

=cut

our %WORKER_TYPE_CAPABILITY_PARAMETER = (
    Mail => 'mail_location',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 validate_restore_handler_parameter( $HANDLER )

=cut

sub validate_restore_handler_parameter ( $str, $worker_type ) {

    if ( !grep { $_ eq $str } Cpanel::LinkedNode::Alias::Constants::ALL_PSEUDO_ALIASES ) {
        require Cpanel::LinkedNode;

        Cpanel::LinkedNode::Alias::validate_linked_node_alias_or_die($str);

        Cpanel::LinkedNode::verify_node_capabilities(
            alias        => $str,
            capabilities => [$worker_type],
        );
    }

    return;
}

=head2 $worker_type_why_hr = get_mismatch_stored_linked_nodes( $EXTRACTDIR )

This examines the contents of $EXTRACTDIR and reports all stored linked nodes
that the (new) host system cannot honor.

The return is a reference to a hash of ( $worker_type => $reason_why ).
Any $worker_type listed here cannot use the stored worker as the “existing”
one in an account restore.

=cut

sub get_mismatch_stored_linked_nodes ($extractdir) {

    my $worker_conf = Whostmgr::Transfers::Utils::WorkerNodesObj->new($extractdir);

    my @worker_types = sort $worker_conf->get_worker_types();

    my %worker_type_why;

    for my $worker_type (@worker_types) {

        my $conf_alias = $worker_conf->get_type_alias($worker_type);
        my $hostname   = $worker_conf->get_type_hostname($worker_type);

        my $skip_reason;

        my $conf_obj = Cpanel::LinkedNode::User::get_node_configuration_if_exists($conf_alias);

        if ($conf_obj) {
            if ( $hostname ne $conf_obj->hostname() ) {
                $skip_reason =
                  locale()->maketext( 'The account archive describes a “[_1]” linked node with alias “[_2]” and hostname “[_3]”. This system uses a linked node with that alias, but the linked node’s hostname ([_4]) does not match the archive. Because of this, the restored account will not use a “[_1]” linked node.', $worker_type, $conf_alias, $hostname, $conf_obj->hostname() );
            }
        }
        else {
            $skip_reason = locale()->maketext( 'The account archive describes a “[_1]” linked node with alias “[_2]”. This system does not use a linked node with that alias. Because of this, the restored account will not use a “[_1]” linked node.', $worker_type, $conf_alias );
        }

        if ($skip_reason) {
            $worker_type_why{$worker_type} = $skip_reason;
        }
    }

    return \%worker_type_why;
}

1;
