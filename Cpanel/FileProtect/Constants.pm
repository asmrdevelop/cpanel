package Cpanel::FileProtect::Constants;

# cpanel - Cpanel/FileProtect/Constants.pm                 Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {

    #"/home", "/home2", etc.
    DEFAULT_MOUNT_PERMS => 0711,

    #"/home/user1", "/home/user2", etc.
    DEFAULT_HOMEDIR_PERMS => 0711,
    OS_ACLS_HOMEDIR_PERMS => 0750,

    #If neither FileProtect nor ACLs are on, docroot and .htpasswds
    #directores have these perms.
    DEFAULT_DOCROOT_PERMS => 0755,

    #If FileProtect OR ACLs is on, docroot and .htpasswds dirs have these perms.
    FILEPROTECT_OR_ACLS_DOCROOT_PERMS => 0750
};

1;
