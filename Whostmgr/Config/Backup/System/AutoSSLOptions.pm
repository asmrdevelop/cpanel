package Whostmgr::Config::Backup::System::AutoSSLOptions;

# cpanel - Whostmgr/Config/Backup/System/AutoSSLOptions.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::System::AutoSSLOptions

=head1 DESCRIPTION

This module implements backups for inter-server transfers of
AutoSSL options. (i.e., exclusive of actual provider choice/setup)

It is a subclass of L<Whostmgr::Config::Backup::Base::JSON>.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Backup::Base::JSON );

use Cpanel::SSL::Auto::Config::Read ();

#----------------------------------------------------------------------

sub _get_backup_structure {
    return Cpanel::SSL::Auto::Config::Read->new()->get_metadata();
}

1;
