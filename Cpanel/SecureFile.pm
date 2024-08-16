package Cpanel::SecureFile;

# cpanel - Cpanel/SecureFile.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::FileUtils::TouchFile ();

#Sets a file's permissions to 0600.
#If the file doesn't exist, this creates it.
sub set_permissions {
    my ($db_file) = @_;
    if ( -e $db_file ) {
        if ( ( ( stat(_) )[2] & 07777 ) != 0600 ) {
            chmod 0600, $db_file;
        }
        if ( -e $db_file . '.cache' && ( ( stat(_) )[2] & 07777 ) != 0600 ) {
            chmod 0600, $db_file . '.cache';
        }
    }
    else {

        # Create the file so that store_ref sets the correct permissions
        Cpanel::FileUtils::TouchFile::touchfile($db_file);
        chmod 0600, $db_file;
    }

    return;
}

1;
