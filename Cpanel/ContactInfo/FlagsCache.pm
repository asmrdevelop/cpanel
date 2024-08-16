
# cpanel - Cpanel/ContactInfo/FlagsCache.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::ContactInfo::FlagsCache;

use strict;

use Cpanel::ConfigFiles                           ();
use Cpanel::MultiUserDirStore::Flags              ();
use Cpanel::MultiUserDirStore::VirtualUser::Flags ();

our $USER_NOTIFICATIONS_FLAG_STORAGE_DIR = 'state';

sub get_user_flagcache {
    my (%OPTS) = @_;

    return Cpanel::MultiUserDirStore::Flags->new( 'dir' => $Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR, 'subdir' => $USER_NOTIFICATIONS_FLAG_STORAGE_DIR, %OPTS );
}

sub get_virtual_user_flagcache {
    my (%OPTS) = @_;

    return Cpanel::MultiUserDirStore::VirtualUser::Flags->new( 'dir' => $Cpanel::ConfigFiles::USER_NOTIFICATIONS_DIR, 'subdir' => $USER_NOTIFICATIONS_FLAG_STORAGE_DIR, %OPTS );
}

1;
