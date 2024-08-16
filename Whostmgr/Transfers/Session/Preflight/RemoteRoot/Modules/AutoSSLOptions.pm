package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::AutoSSLOptions;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/AutoSSLOptions.pm
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

Subclasses L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base>.

=cut

#----------------------------------------------------------------------

use parent 'Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse';

use constant _BACKUP_NAMESPACE => 'cpanel::system::autossloptions';

#----------------------------------------------------------------------

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/AutoSSLOptions* for how we
# backup and restore the data

=head1 METHODS

=head2 name()

Override base class.

=cut

sub name {
    my ($self) = @_;
    return $self->_locale()->maketext("[asis,AutoSSL] Options");
}

1;
