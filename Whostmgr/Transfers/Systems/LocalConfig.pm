package Whostmgr::Transfers::Systems::LocalConfig;

# cpanel - Whostmgr/Transfers/Systems/LocalConfig.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::LocalConfig

=head1 DESCRIPTION

This module updates the user’s local configuration. It’s a good place
to put configuration changes that need to happen between restoration of
the configuration and any propagation of those configurations to active
services.

=cut

#----------------------------------------------------------------------

use parent qw(
  Whostmgr::Transfers::Systems
);

use constant {
    get_phase                => 70,                         # right before ZoneFile
    get_restricted_available => 1,
    get_prereq               => [ 'userdata', 'CpUser' ],
};

#----------------------------------------------------------------------

=head1 METHODS

The following just implement the standard restore module logic:

=over

=item * C<get_summary>

=item * C<restricted_restore>

=item * C<unrestricted_restore>

=back

=cut

sub get_summary ($self) {
    return [ $self->_locale()->maketext('This module updates the local user’s configuration.') ];
}

sub unrestricted_restore ($self) {

    # If the account isn’t new, then we want to undo any active service
    # proxying since we assume that the intent is for all services to be
    # hosted on this server (or its child nodes).
    if ( !$self->utils()->{'flags'}{'createacct'} ) {
        require Cpanel::AccountProxy::Transaction;

        $self->start_action('Unsetting local service proxying …');
        Cpanel::AccountProxy::Transaction::unset_all_backends( $self->newuser() );
    }

    return 1;
}

*restricted_restore = *unrestricted_restore;

1;
