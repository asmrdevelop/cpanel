
# cpanel - Whostmgr/Transfers/Session/Remotes.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::Transfers::Session::Remotes;

use strict;
use warnings;

sub get_locations_for_server_type {
    my ($server_type) = @_;

    die 'undef is not supported' if ( !$server_type );

    my %defaults = ( 'updateuserdomains_script' => 'updateuserdomains-universal' );

    my %REMOTE_TYPES = (
        'spectro'     => { 'pkgacct_script' => 'pkgacct-ciXost' },
        'ensim'       => { 'pkgacct_script' => 'pkgacct-enXim', 'packages_script' => 'packages-enXim' },
        'plesk'       => { 'pkgacct_script' => 'pkgacct-pXa',   'packages_script' => 'packages-pXa', 'dump_databases_and_users_script' => 'dump_databases_and_users-plesk' },
        'dsm'         => { 'pkgacct_script' => 'pkgacct-dXm' },
        'alabanza'    => { 'pkgacct_script' => 'pkgacct-ala' },
        'directadmin' => { 'pkgacct_script' => 'pkgacct-da' },
        'sphera'      => { 'pkgacct_script' => 'pkgacct-sXh' }
    );

    if ( !$REMOTE_TYPES{$server_type} ) {
        die "$server_type is not supported";
    }

    return {
        %defaults, %{ $REMOTE_TYPES{$server_type} },
    };
}

1;
