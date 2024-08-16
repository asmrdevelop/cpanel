package Whostmgr::Setup::EULA;

# cpanel - Whostmgr/Setup/EULA.pm                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Setup::EULA

=head1 SYNOPSIS

    if (Whostmgr::Setup::EULA::is_accepted()) { .. }

=head1 DESCRIPTION

This simple module provides an interface to storage about the
acceptance of cPanel & WHM’s end-user license agreement (EULA).

=cut

#----------------------------------------------------------------------

our $_BASEDIR = '/var/cpanel/activate';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_accepted()

Returns a boolean that indicates whether the EULA is accepted on this
server.

=cut

sub is_accepted () {
    return Whostmgr::Setup::EULA::_Filesys->is_on();
}

=head2 set_accepted()

Sets the EULA as accepted on this server.

=cut

sub set_accepted () {
    local ( $@, $! );
    require Cpanel::SafeDir::MK;
    Cpanel::SafeDir::MK::safemkdir( $_BASEDIR, '0700' );

    Whostmgr::Setup::EULA::_Filesys->set_on();

    return;
}

=head2 set_not_accepted()

Sets the EULA as not accepted on this server. This is only useful
when preparing the server for cloning.

=cut

sub set_not_accepted () {
    local ( $@, $! );
    require Cpanel::SafeDir::MK;
    Cpanel::SafeDir::MK::safemkdir( $_BASEDIR, '0700' );

    Whostmgr::Setup::EULA::_Filesys->set_off();

    return;
}

#----------------------------------------------------------------------

package Whostmgr::Setup::EULA::_Filesys;

use parent 'Cpanel::Config::TouchFileBase';

use constant _FILENAME => '2024-05.v01.GDPR.CPWHMEULA';

sub _TOUCH_FILE {
    return "$Whostmgr::Setup::EULA::_BASEDIR/" . _FILENAME;
}

1;
