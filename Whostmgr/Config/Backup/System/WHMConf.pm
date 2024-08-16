package Whostmgr::Config::Backup::System::WHMConf;

# cpanel - Whostmgr/Config/Backup/System/WHMConf.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use Cpanel::Services::Enabled ();
use Cpanel::TempFile          ();

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::system::whmconf'} = {};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{'cpanel::system::whmconf'}  = {};

    $files_to_copy->{'/etc/wwwacct.conf'}         = { "dir" => "cpanel/system/whmconf/config" };
    $files_to_copy->{'/etc/wwwacct.conf.shadow'}  = { "dir" => "cpanel/system/whmconf/config" };
    $files_to_copy->{'/etc/cpupdate.conf'}        = { "dir" => "cpanel/system/whmconf/config" };
    $files_to_copy->{'/etc/stats.conf'}           = { "dir" => "cpanel/system/whmconf/config" };
    $files_to_copy->{'/etc/my.cnf'}               = { "dir" => "cpanel/system/whmconf/config" };
    $files_to_copy->{'/var/cpanel/cpanel.config'} = { "dir" => "cpanel/system/whmconf/config" };

    $dirs_to_copy->{'/var/cpanel/acllists'} = { 'archive_dir' => 'cpanel/system/whmconf/config/acllists' };

    $self->{'temp_obj'} = Cpanel::TempFile->new();
    my $temp_dir = $self->{'temp_dir'} = $self->{'temp_obj'}->dir();
    if ( open( my $disabled_list_fh, '>', "$temp_dir/services.config" ) ) {
        print {$disabled_list_fh} "nameserver=" . ( Cpanel::Services::Enabled::is_enabled('dns')  ? 1 : 0 ) . "\n";
        print {$disabled_list_fh} "ftpserver=" .  ( Cpanel::Services::Enabled::is_enabled('ftp')  ? 1 : 0 ) . "\n";
        print {$disabled_list_fh} "mailserver=" . ( Cpanel::Services::Enabled::is_enabled('mail') ? 1 : 0 ) . "\n";
    }
    else {
        return ( 0, __PACKAGE__ . ": failed to create services.config: $!" );
    }

    $files_to_copy->{"$temp_dir/services.config"} = { "dir" => "cpanel/system/whmconf/config" };

    return ( 1, __PACKAGE__ . ": ok" );

}

sub post_backup {
    my $self = shift;

    my $temp_dir = $self->{'temp_dir'};
    if ( ( $temp_dir =~ tr/\/// ) < 1 ) {
        return ( 0, "Backup Path: $temp_dir cannot be a top or second level directory" );    # ok to not remove because invalid
    }

    delete $self->{'temp_obj'};                                                              # will rm -rf the dir

    return;
}

sub query_module_info {
    my ($self) = @_;

    require Cpanel::Version::Full;
    my $VERSION = Cpanel::Version::Full::getversion();

    if ( $VERSION !~ m/[\d\.]+/ ) {
        $VERSION = 'Unknown';
    }

    my $output = "cPanel_Version=$VERSION";

    return $output;
}

1;
