package Cpanel::Market::Sync;

# cpanel - Cpanel/Market/Sync.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::License          ();
use Cpanel::LoadModule       ();
use Cpanel::Daemonizer::Tiny ();
use Cpanel::ConfigFiles      ();
use Cpanel::FileUtils::Open  ();

use Try::Tiny;

sub sync_local_config_to_cpstore_in_background {
    return if !Cpanel::License::is_licensed();
    Cpanel::Daemonizer::Tiny::run_as_daemon(
        sub {
            local $SIG{'__DIE__'}  = 'DEFAULT';
            local $SIG{'__WARN__'} = 'DEFAULT';

            ####
            # The next two calls are unchecked because it cannot be captured when running as a daemon
            Cpanel::FileUtils::Open::sysopen_with_real_perms( \*STDERR, $Cpanel::ConfigFiles::CPANEL_ROOT . '/logs/error_log', 'O_WRONLY|O_APPEND|O_CREAT', 0600 );
            open( STDOUT, '>&', \*STDERR ) || warn "Failed to redirect STDOUT to STDERR";

            Cpanel::LoadModule::load_perl_module('Cpanel::Market');

            # This will send our local pricing and commision
            # account info to the store so the new license
            # is updated with this information
            Cpanel::Market::sync_local_config_to_cpstore();

            # This is just to keep the cache file up to date
            # in order to ensure the WHM UI does not have to fetch it
            # upon login
            require Cpanel::Market::Provider::cPStore;
            try {
                () = Cpanel::Market::Provider::cPStore::get_products_list();
            }
            catch {
                require Cpanel::Debug;
                Cpanel::Debug::log_warn("Failed to fetch cPStore products list: $_");
            };

            return 1;
        }
    );

    return 1;
}

1;
