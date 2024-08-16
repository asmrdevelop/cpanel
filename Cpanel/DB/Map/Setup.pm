package Cpanel::DB::Map::Setup;

# cpanel - Cpanel/DB/Map/Setup.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles      ();
use Cpanel::Debug            ();
use Cpanel::SafeDir::MK      ();
use Cpanel::FileUtils::Chown ();

my $DB_MAP_DIR_PERMS = 0751;

sub initialize {

    my $dir = _base_directory();

    # Ensure database directory exists
    if ( -d $dir ) {

        # security: fix owner and permission ( do nothing if correctly set )
        Cpanel::FileUtils::Chown::check_and_fix_owner_and_permissions_for(
            path        => $dir,
            uid         => 0,
            gid         => 0,
            octal_perms => $DB_MAP_DIR_PERMS,
        );
    }
    else {
        if ( -e $dir ) {

            Cpanel::Debug::log_warn("Renaming existing file $dir to $dir.setupdbmap_saved.");
            rename $dir, $dir . '.setupdbmap_saved';
        }
        Cpanel::Debug::log_info('Creating DB Mapping storage directory');
        Cpanel::SafeDir::MK::safemkdir( $dir, $DB_MAP_DIR_PERMS ) or Cpanel::Debug::log_die("Failed to initialize DB mapping storage directory $dir: $!");
    }
    return;
}

sub _base_directory {
    return $Cpanel::ConfigFiles::DATABASES_INFO_DIR;
}

1;
