package Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::ModSecurity;

# cpanel - Whostmgr/Transfers/Session/Preflight/RemoteRoot/Modules/ModSecurity.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Transfers::Session::Preflight::RemoteRoot::Modules::ModSecurity

=head1 DESCRIPTION

A preflight module to verify that a remote server is able to transfer
its ModSecurity configuration to the local server.

Subclasses L<Whostmgr::Transfers::Session::Preflight::RemoteRoot::Base>.

=cut

#----------------------------------------------------------------------

use parent (
    'Whostmgr::Transfers::Session::Preflight::RemoteRoot::SimpleParse',
);

use constant _BACKUP_NAMESPACE => 'cpanel::system::modsecurity';

#----------------------------------------------------------------------

# See /usr/local/cpanel/Whostmgr/Transfers/Session/Items/ModSecurity*
# for how we backup and restore the data.

1;
