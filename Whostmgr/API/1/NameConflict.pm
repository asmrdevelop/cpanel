package Whostmgr::API::1::NameConflict;

# cpanel - Whostmgr/API/1/NameConflict.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Accounts::NameConflict ();
use Whostmgr::API::1::Utils          ();

use constant NEEDS_ROLE => {
    verify_new_username             => undef,
    verify_new_username_for_restore => undef,
};

sub verify_new_username_for_restore {
    my ( $args, $metadata ) = @_;
    my $user = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    Whostmgr::Accounts::NameConflict::verify_new_name_for_restore($user);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

sub verify_new_username {
    my ( $args, $metadata ) = @_;
    my $user = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'user' );
    Whostmgr::Accounts::NameConflict::verify_new_name($user);
    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

1;
