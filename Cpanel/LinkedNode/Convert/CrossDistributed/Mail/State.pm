package Cpanel::LinkedNode::Convert::CrossDistributed::Mail::State;

# cpanel - Cpanel/LinkedNode/Convert/CrossDistributed/Mail/State.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::Convert::CrossDistributed::Mail::State

=head1 SYNOPSIS

XXXX

=head1 DESCRIPTION

This module holds state data for a mail cross-distribution.
It subclasses L<Cpanel::Hash::Strict>.

=cut

#----------------------------------------------------------------------

use parent 'Cpanel::LinkedNode::Convert::Common::Mail::FromRemoteStateBase';

use constant _PROPERTIES => (
    __PACKAGE__->SUPER::_PROPERTIES(),

    'target_node_obj',
    'records_to_update',
    'target_work_dir',

    # Should these be refactored to a ToRemoteStateBase class
    # to share w/ ToDistributed?
    'target_homedir_root',
    'target_listaccts_hr',

    'target_user_api_token',

    'old_local_manual_mx',
);

*_source_server_claims_ip       = __PACKAGE__->can('_Source_server_claims_ip');
*_source_server_claims_domain_p = __PACKAGE__->can('_Source_server_claims_domain_p');

1;
