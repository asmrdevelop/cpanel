
# cpanel - Cpanel/UserManager/Record/Lite.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::UserManager::Record::Lite;

use strict;
use base 'Cpanel::UserManager::Record';

sub VALIDATION { return 0 }

sub upgrade_obj {    ##no critic(RequireArgUnpacking)
    return bless $_[0], 'Cpanel::UserManager::Record';
}

1;
