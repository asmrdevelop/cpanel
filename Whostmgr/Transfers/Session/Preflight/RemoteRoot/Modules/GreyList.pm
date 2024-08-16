package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::GreyList;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/GreyList.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::GreyList

=head1 DESCRIPTION

A preflight module to verify that a remote server is able to transfer
its Greylisting configuration to the local server.

This indicates an error if either the remote server has no Greylist
backup functionality or the local server’s Greylisting is disabled.

Subclasses L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base>.

=cut

#----------------------------------------------------------------------

use Cpanel::GreyList::Config ();

use parent (
    'Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse',
);

use constant _BACKUP_NAMESPACE => 'cpanel::system::greylist';

#----------------------------------------------------------------------

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/GreyList* for how we
# backup and restore the data

sub _errors_and_warnings ( $self, $remote_data ) {

    my @errors;

    if ( !Cpanel::GreyList::Config::is_enabled() ) {
        push @errors, $self->_locale()->maketext( 'You must enable [asis,Greylisting] on this server to update its configuration.', $self->name() );
    }

    return ( \@errors, [] );
}

1;
