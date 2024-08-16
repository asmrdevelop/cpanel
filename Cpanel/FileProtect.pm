package Cpanel::FileProtect;

# cpanel - Cpanel/FileProtect.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module only concerns the stored on/off FileProtect state.
# To enable or disable fileprotect, use scripts/enablefileprotect
# and scripts/disablefileprotect.
#
# See base class for full documentation.
#----------------------------------------------------------------------

use strict;
use warnings;

use Cpanel::Config::CpConfGuard ();

use parent qw( Cpanel::Config::TouchFileBase );

sub _TOUCH_FILE {
    return '/var/cpanel/fileprotect';
}

sub _config_setting {
    return 'enablefileprotect';
}

sub set_on {
    my ($class) = @_;

    my $guard = Cpanel::Config::CpConfGuard->new;
    $guard->set( _config_setting(), 1 );
    $guard->save;

    return $class->SUPER::set_on();
}

sub set_off {
    my ($class) = @_;

    my $guard = Cpanel::Config::CpConfGuard->new;
    $guard->set( _config_setting(), 0 );
    $guard->save;

    return $class->SUPER::set_off();
}

1;
