package Whostmgr::Transfers::Systems::ResyncHomedir;

# cpanel - Whostmgr/Transfers/Systems/ResyncHomedir.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(
  Whostmgr::Transfers::Systems::Homedir
);

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Systems::ResyncHomedir - Resync the homedir at the end of the transfer

=head1 SYNOPSIS

    use Whostmgr::Transfers::Systems::ResyncHomedir;

    # Only called by the transfer restore system.

=head1 DESCRIPTION

This module will resync the homedir at the end of the transfer if rsync
is available.

=cut

#----------------------------------------------------------------------

# Omit mail because we also have the MailSync module.
use constant _STREAM_EXCLUSIONS => (
    './mail/*',
);

#----------------------------------------------------------------------

=head2 get_phase()

Phase 99 is done right before PostRestoreActions

=cut

sub get_phase {
    return 99;
}

=head2 get_summary()

Provide a summary to display in the UI

=cut

sub get_summary {
    my ($self) = @_;
    return [ $self->_locale()->maketext('This module will resynchronize the home directory from the source server. The module preserves any changes that occurred during the transfer.') ];
}

=head2 get_restricted_available()

Determines if restricted restore mode is available

=cut

sub get_restricted_available {
    return 1;
}

*restricted_restore = *unrestricted_restore;

=head2 unrestricted_restore()

Only intended to be called by the transfer restore system.

=cut

sub unrestricted_restore {
    my ($self) = @_;

    my $stream_config = $self->{'_utils'}{'flags'}{'stream'};
    if ( !$stream_config || !$stream_config->{'rsync'} ) {
        return 1;
    }

    if ( $self->disabled()->{'Homedir'}{'all'} ) {
        return 1;
    }

    return $self->SUPER::unrestricted_restore();
}

1;
