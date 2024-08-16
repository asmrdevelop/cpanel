package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Hulk;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/Hulk.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::Hulk

=head1 DESCRIPTION

A preflight module to verify that a remote server is able to transfer
its Hulk configuration to the local server.

This indicates an error if either the remote server has no Hulk
backup functionality or the local server’s cPHulk is disabled.

Subclasses L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base>.

=cut

#----------------------------------------------------------------------

use Cpanel::Config::Hulk ();

use parent (
    'Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse',
);

use constant _BACKUP_NAMESPACE => 'cpanel::system::hulk';

#----------------------------------------------------------------------

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/Hulk* for how we
# backup and restore the data

sub _errors_and_warnings ( $self, $remote_data ) {

    my @errors;

    if ( !Cpanel::Config::Hulk::is_enabled() ) {
        push @errors, $self->_locale()->maketext('You must enable [asis,cPHulk] on this server to update its configuration.');
    }

    return ( \@errors, [] );
}

1;
