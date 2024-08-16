package Cpanel::Server::CpXfer::cpanel::acctxferrsync;

# cpanel - Cpanel/Server/CpXfer/cpanel/acctxferrsync.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::CpXfer::cpanel::acctxferrsync

=head1 DESCRIPTION

This module implements acctxferrsync for cPanel (the application).

No username is required since a username is given during
authentication.

This module subclasses L<Cpanel::Server::CpXfer::Base::acctxferrsync>.

=cut

#----------------------------------------------------------------------

use parent qw(
  Cpanel::Server::CpXfer::Base::acctxferrsync
  Cpanel::Server::ModularApp::cpanel::ForbidDemo
);

use Cpanel::PwCache ();

sub _get_homedir {

    # Needs to be called with no arguments.
    return Cpanel::PwCache::gethomedir();
}

1;
