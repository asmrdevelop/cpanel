package Whostmgr::Config::Backup::System::Mysql;

# cpanel - Whostmgr/Config/Backup/System/Mysql.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use Whostmgr::Config::Mysql     ();
use Cpanel::MysqlUtils::Version ();

use File::Find;

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::system::mysql'} = {};

    foreach my $cfg_file ( keys %Whostmgr::Config::Mysql::files ) {
        my $special = $Whostmgr::Config::Mysql::files{$cfg_file}{'special'};

        if ( $special eq "present" ) {
            $files_to_copy->{$cfg_file} = { 'dir' => 'cpanel/system/mysql' };
        }
        elsif ( $special eq 'cpanel_config' ) {
            $files_to_copy->{$cfg_file} = { 'dir' => 'cpanel/system/mysql' };
        }
    }

    return ( 1, __PACKAGE__ . ": ok" );
}

sub query_module_info {
    my $version = Cpanel::MysqlUtils::Version::get_mysql_version_with_fallback_to_default();
    return "MySQL_Version=$version";
}

1;
