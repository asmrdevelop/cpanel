package Cpanel::MemUsage::WHM::Banned;

# cpanel - Cpanel/MemUsage/WHM/Banned.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Binary ();

our @BANNED_MEMORY_MODULES = (
    'Cpanel::API',                        # do not use Cpanel::API in whm
    'Cpanel',                             # do not use Cpanel in whm
    'Cpanel::AdminBin',                   # do not use Cpanel in whm
    'Cpanel::AdminBin::Call',             # do not use Cpanel in whm
    'Whostmgr::TweakSettings::Mail',      # these must by dynamicly loaded (we had it compiled in due to an old IncludeDeps bug)
    'Whostmgr::TweakSettings::Main',      # these must by dynamicly loaded (we had it compiled in due to an old IncludeDeps bug)
    'Whostmgr::TweakSettings::Apache',    # these must by dynamicly loaded (we had it compiled in due to an old IncludeDeps bug)
);

sub check {
    return 1 if Cpanel::Binary::is_binary();    # No need to run this check if we already made it though compile
    foreach my $mod (@BANNED_MEMORY_MODULES) {
        my $mod_path = $mod;
        $mod_path =~ s{::}{/}g;
        $mod_path .= '.pm';
        if ( $INC{$mod_path} && $INC{$mod_path} ne '__DISABLED__' ) {
            require Carp;
            Carp::confess("$mod is not permitted to be compiled into this application.");
        }

    }
    return 1;
}

sub add_exception {
    my ($exception) = @_;

    @BANNED_MEMORY_MODULES = grep { $_ ne $exception } @BANNED_MEMORY_MODULES;

    return 1;
}

1;
