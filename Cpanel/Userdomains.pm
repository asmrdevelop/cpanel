package Cpanel::Userdomains;

# cpanel - Cpanel/Userdomains.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::LoadModule::Utils ();

our $PATH_TO_UPDATEUSERDOMAINS = '/usr/local/cpanel/scripts/updateuserdomains';

my $core;
my @clearcache_calls = ( 'Cpanel::AcctUtils::DomainOwner::Tiny', 'Cpanel::AcctUtils::Owner' );

sub updateuserdomains {
    my $force = shift;

    require Cpanel::Userdomains::CORE;

    $core ||= Cpanel::Userdomains::CORE->new();

    my $ret = $core->update( 'force' => ( $force || 0 ) );

    foreach my $mod (@clearcache_calls) {
        if ( Cpanel::LoadModule::Utils::module_is_loaded($mod) ) {
            $mod->can('clearcache')->();
        }
    }

    return $ret;
}

1;
