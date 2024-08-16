package Whostmgr::Accounts::Suspension::Base;

# cpanel - Whostmgr/Accounts/Suspension/Base.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# Base class for account suspension and unsuspension.
#
# This is a base class. See subclasses for usage examples.
#----------------------------------------------------------------------

use cPstrict;

use parent qw( Whostmgr::Accounts::CommandQueue );

use Cpanel::PostgresAdmin::Check ();

use constant _ALWAYS_MODULES => (
    'SSH',
    'WorkerNodes',
    'DynamicWebContent',
);

#NOTE: overridden in tests
sub _helper_modules_to_use ($class) {
    my @modules = _ALWAYS_MODULES();

    if ( Cpanel::PostgresAdmin::Check::is_enabled_and_configured() ) {
        push @modules, 'Postgresql';
    }

    return @modules;
}

sub _helper_module_namespace_root {
    return __PACKAGE__ =~ s<::[^:]+\z><>r;
}

1;
