package Whostmgr::AcctInfo::Owner;

# cpanel - Whostmgr/AcctInfo/Owner.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::AcctUtils::Owner ();
use Whostmgr::ACLS           ();

sub checkowner {
    my $owner = shift || return;
    my $user  = shift || return;
    return 1 if Whostmgr::ACLS::hasroot();
    return   if $user eq 'root';

    my $real_owner = Cpanel::AcctUtils::Owner::getowner($user);
    return if !$real_owner;
    return $real_owner eq $owner ? 1 : 0;

}

1;
