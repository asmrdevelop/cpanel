package Cpanel::Sys::Hardware::Memory;

# cpanel - Cpanel/Sys/Hardware/Memory.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::OSSys::Env                   ();
use Cpanel::Sys::Hardware::Memory::Linux ();
use Cpanel::Sys::Hardware::Memory::Vzzo  ();    # PPI USE OK - used by get_module / _dispatch

sub get_module {
    my ($env_type) = @_;
    $env_type ||= Cpanel::OSSys::Env::get_envtype();
    my $module = 'Cpanel::Sys::Hardware::Memory::Linux';
    $module = 'Cpanel::Sys::Hardware::Memory::Vzzo' if ( $env_type eq 'virtuozzo' || $env_type eq 'vzcontainer' );

    return $module;
}

sub _dispatch {
    my ( $func, @args ) = @_;

    my $module = get_module();
    my $call   = $module->can($func) or die "Can’t find function “$func”!";

    my $value = $call->(@args);

    # Virtuozzo bean counters sometimes report unlimited. Fall back to standard checks when that happens.
    if ( $module eq 'Cpanel::Sys::Hardware::Memory::Vzzo' && $value =~ m/^un/ ) {
        $call  = Cpanel::Sys::Hardware::Memory::Linux->can($func) or die "Can’t find function “Cpanel::Sys::Hardware::Memory::Linux::$func”!";
        $value = $call->(@args);
    }

    return $value;
}

sub get_installed {
    return _dispatch('get_installed');
}

sub get_available {
    return _dispatch('get_available');
}

sub get_used {
    return _dispatch('get_used');
}

sub get_swap {
    return _dispatch('get_swap');
}

1;
