package Whostmgr::Config::Apache;

# cpanel - Whostmgr/Config/Apache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::EA4 ();
use Cpanel::SafeRun::Errors    ();

our $ea4_custom_profile_dir        = '/etc/cpanel/ea4/profiles/custom';
our $ea4_custom_profile_backup_dir = 'cpanel/easy/apache/etc/cpanel/ea4/profiles/custom';

our $ea4_conf_d_dir        = '/etc/apache2/conf.d';
our $ea4_conf_d_backup_dir = 'cpanel/easy/apache/etc/apache2/conf.d';

our $main_yaml_dir        = '/var/cpanel/easy/apache/profile';
our $main_yaml_backup_dir = 'cpanel/easy/apache/var/cpanel/easy/apache/profile';

our $secdatadir        = '/var/cpanel/secdatadir';
our $secdatadir_backup = "cpanel/easy/apache/var/cpanel/secdatadir";

our $varcpanel = '/var/cpanel';

our $modsec_datastore = "cpanel/easy/apache/var/cpanel/modsec_cpanel_conf_datastore";

our %apache_files = (
    '/etc/cpanel/ea4'        => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/etc/cpanel/ea4/" },
    '/var/cpanel/easy'       => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/var/cpanel/easy/" },
    '/etc/apache2/conf.d'    => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/etc/apache2/conf.d/" },
    '/etc/apache2/conf'      => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/etc/apache2/conf/" },
    '/usr/local/apache/conf' => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/usr/local/apache/conf/" },
    '/var/cpanel/secdatadir' => { 'special' => "dir", 'archive_dir' => "cpanel/easy/apache/var/cpanel/secdatadir" },

    '/var/cpanel/modsec_cpanel_conf_datastore' => { 'special' => "present" },
);

sub get_current_profile_file {
    return $ea4_custom_profile_dir . '/cpconftool_current_profile.json';
}

sub get_backup_profile_file {
    my ($backup_path) = @_;
    return $backup_path . "/" . $ea4_custom_profile_backup_dir . '/cpconftool_current_profile.json';
}

sub ensure_custom_profile_dir_exists {
    File::Path::make_path($ea4_custom_profile_dir) if ( !-e $ea4_custom_profile_dir );
    return;
}

sub create_current_profile {

    # if we are EA4 then get a snapshot of the current profile
    my $current_profile_file = get_current_profile_file();
    unlink $current_profile_file if -e $current_profile_file;

    if ( Cpanel::Config::Httpd::EA4::is_ea4() ) {
        ensure_custom_profile_dir_exists();
        my $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/bin/ea_current_to_profile', "--output=$current_profile_file" );
    }

    return;
}

1;
