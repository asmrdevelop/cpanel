package Whostmgr::Config::Backup::System::Hulk;

# cpanel - Whostmgr/Config/Backup/System/Hulk.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::Config::Backup::System::Hulk

=head1 DESCRIPTION

This module implements Hulk backups for inter-server configuration
transfers.

=cut

#----------------------------------------------------------------------

use parent qw( Whostmgr::Config::Backup::Base::JSON );

use Whostmgr::API::1::Utils::Execute ();

sub _get_backup_structure ($self) {

    my $general_hr = Whostmgr::API::1::Utils::Execute::execute_or_die( 'cPHulk', 'load_cphulk_config' );

    my $struct_hr = { general => $general_hr->get_data()->{cphulk_config} };

    for my $list_name (qw(white black)) {

        my $ips_hr = Whostmgr::API::1::Utils::Execute::execute_or_die(
            'cPHulk', 'read_cphulk_records',
            {
                skip_enabled_check => 1,
                list_name          => $list_name,
            }
        );

        $struct_hr->{$list_name} = $ips_hr->get_data()->{ips_in_list};
    }

    return $struct_hr;
}

1;
