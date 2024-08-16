package Whostmgr::Groups;

# cpanel - Whostmgr/Groups.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache::Group ();

sub getgroups {
    return [ Cpanel::PwCache::Group::getgroups(@_) ];
}

sub remove_user_from_group {
    my ( $user, $group ) = @_;
    require Cpanel::SysAccounts;
    return Cpanel::SysAccounts::remove_user_from_group( $group, $user );
}

sub add_user_to_group {
    my ( $user, $group ) = @_;
    require Cpanel::SysAccounts;
    return Cpanel::SysAccounts::add_user_to_group( $group, $user );
}

1;
