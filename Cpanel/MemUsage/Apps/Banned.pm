package Cpanel::MemUsage::Apps::Banned;

# cpanel - Cpanel/MemUsage/Apps/Banned.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Binary ();

our @BANNED_MEMORY_MODULES = (
    'DateTime',          # suggest Cpanel::LoadModule::load_perl_module, see CPANEL-1151
    'Digest::SHA1',      # use Digest::SHA since we already load it
    'Cpanel::Logger',    # lazy load the logger or use Cpanel::Debug::log_* as most runs should be error free
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
