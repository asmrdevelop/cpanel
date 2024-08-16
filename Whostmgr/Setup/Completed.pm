package Whostmgr::Setup::Completed;

# cpanel - Whostmgr/Setup/Completed.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Setup::Completed

=head1 SYNOPSIS

    if (Whostmgr::Setup::Completed::is_complete()) { .. }

=head1 DESCRIPTION

This simple module provides an interface to storage about the
completion of WHM’s initial setup.

=cut

#----------------------------------------------------------------------

our $_PATH = '/etc/.whostmgrft';

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $yn = is_complete()

Returns a boolean that indicates whether WHM’s initial setup is complete.

=cut

sub is_complete () {
    return Whostmgr::Setup::Completed::_Filesys->is_on();
}

=head2 set_complete()

Records completion of WHM’s initial setup.

=cut

sub set_complete () {
    Whostmgr::Setup::Completed::_Filesys->set_on();

    return;
}

=head2 set_not_complete()

Records that WHM initial setup is NOT complete (even if it has previously been completed).

=cut

sub set_not_complete () {
    Whostmgr::Setup::Completed::_Filesys->set_off();

    return;
}

#----------------------------------------------------------------------

package Whostmgr::Setup::Completed::_Filesys;

use parent 'Cpanel::Config::TouchFileBase';

sub _TOUCH_FILE {
    return $Whostmgr::Setup::Completed::_PATH;
}

1;
