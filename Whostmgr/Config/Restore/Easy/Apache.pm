package Whostmgr::Config::Restore::Easy::Apache;

# cpanel - Whostmgr/Config/Restore/Easy/Apache.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base);

use Cpanel::Config::Httpd::EA4   ();
use Cpanel::Config::CpConfGuard  ();
use Cpanel::Config::LoadConfig   ();
use Cpanel::HttpUtils::ApRestart ();
use Cpanel::JSON                 ();
use Cpanel::SafeRun::Errors      ();

use Whostmgr::Config::Apache  ();
use Whostmgr::Config::Restore ();

use Whostmgr::API::1::ModSecurity   ();
use Whostmgr::ModSecurity::Settings ();

use File::Basename ();

use Try::Tiny;

sub _unlink {    # provides safe testability
    my ($fname) = @_;

    unlink $fname;

    return;
}

sub _restore {
    my $self   = shift;
    my $parent = shift;

    my $backup_path = $parent->{'backup_path'};
    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );
    return ( 0, "version file missing from backup" )     if !-e "$backup_path/cpanel/easy/apache/version";

    $self->{'source_is_ea4'} = 0;
    $self->{'source_is_ea4'} = 1 if -e "$backup_path/cpanel/easy/apache/etc/cpanel/ea4/is_ea4";

    # load the modsec vendors for later post restore

    my $modsec_vendor;

    my $modsec_vendor_json = "$backup_path/cpanel/easy/apache/modsec_vendor.json";
    $modsec_vendor = Cpanel::JSON::LoadFile($modsec_vendor_json) if ( -e $modsec_vendor_json );

    $self->{'modsec_vendor'} = $modsec_vendor if $modsec_vendor;

    my $modsec_settings;

    my $modsec_settings_json = "$backup_path/cpanel/easy/apache/modsec_settings.json";
    $modsec_settings = Cpanel::JSON::LoadFile($modsec_settings_json) if ( -e $modsec_settings_json );

    $self->{'modsec_settings'} = $modsec_settings if $modsec_settings;

    my $var_easy_archive = $Whostmgr::Config::Apache::apache_files{'/var/cpanel/easy'}->{'archive_dir'};
    my $var_easy         = "$backup_path/$var_easy_archive";

    if ( -e $var_easy ) {
        $parent->{'dirs_to_copy'}->{'/var/cpanel/easy'} = { 'archive_dir' => $var_easy_archive };
    }

    if ( !$self->{'source_is_ea4'} && !-e "$backup_path/$Whostmgr::Config::Apache::main_yaml_backup_dir/_main.yaml" ) {

        # put modsec rules in place
        $self->loadModsecVendors();
        $self->loadModsecSettings();
        return ( 1, "EA3 source missing _main.yaml file... leaving current profile unchanged." );
    }

    # to make sure there are no problems placing the files where we want them,
    # we will migrate to EA4 here, if need to.

    $self->{'target_is_ea4'} = Cpanel::Config::Httpd::EA4::is_ea4();

    if ( !$self->{'target_is_ea4'} && $self->{'source_is_ea4'} ) {
        return ( 0, "Can not restore EA4 on this EA4-less machine" );
    }

    if ( -e "$backup_path/$Whostmgr::Config::Apache::ea4_custom_profile_backup_dir" ) {
        $parent->{'dirs_to_copy'}->{$Whostmgr::Config::Apache::ea4_custom_profile_dir} = { 'archive_dir' => 'cpanel/easy/apache/etc/cpanel/ea4/profiles/custom' };
    }

    if ( -e "$backup_path/$Whostmgr::Config::Apache::main_yaml_backup_dir/_main.yaml" ) {
        $parent->{'files_to_copy'}->{"$backup_path/$Whostmgr::Config::Apache::main_yaml_backup_dir/_main.yaml"} = { 'dir' => $Whostmgr::Config::Apache::main_yaml_dir, "file" => "_main.yaml" };
    }

    if ( -e "$backup_path/$Whostmgr::Config::Apache::secdatadir_backup" ) {
        $parent->{'dirs_to_copy'}->{$Whostmgr::Config::Apache::secdatadir} = { 'archive_dir' => $Whostmgr::Config::Apache::secdatadir_backup };
    }

    if ( -e "$backup_path/$Whostmgr::Config::Apache::modsec_datastore" ) {
        $parent->{'files_to_copy'}->{"$backup_path/$Whostmgr::Config::Apache::modsec_datastore"} = { 'dir' => $Whostmgr::Config::Apache::varcpanel, "file" => "modsec_cpanel_conf_datastore" };
    }

    Whostmgr::Config::Restore::restore_ifexists( $parent, "$backup_path/cpanel/easy/apache/other",         '/var/cpanel/conf/apache',         'local',          1 );
    Whostmgr::Config::Restore::restore_ifexists( $parent, "$backup_path/cpanel/easy/apache/other",         '/var/cpanel/conf/apache',         'main',           1 );
    Whostmgr::Config::Restore::restore_ifexists( $parent, "$backup_path/cpanel/easy/apache/conf_includes", '/usr/local/apache/conf/includes', '*',              1 );
    Whostmgr::Config::Restore::restore_ifexists( $parent, "$backup_path/cpanel/easy/apache/templates",     '/var/cpanel/templates',           'apache*/*local', 1 );

    # piped log configuration
    # will be handled in post restore

    my $temp_config = {};
    Cpanel::Config::LoadConfig::loadConfig( "$backup_path/cpanel/easy/apache/tweak/cpanel.config", $temp_config, '=' );

    $self->{'enable_piped_logs'} = $temp_config->{'enable_piped_logs'};

    return ( 1, __PACKAGE__ . ": ok", { 'version' => '1.0.0' } );
}

our $_main_yaml = '/var/cpanel/easy/apache/profile/_main.yaml';

sub loadModsecVendors {
    my ($self) = @_;

    return if ( !exists $self->{'modsec_vendor'} );

    my $modsec_vendor = $self->{'modsec_vendor'};

    my @vendors = keys %{$modsec_vendor};
    foreach my $vendor (@vendors) {
        my $vendor_ref = $modsec_vendor->{$vendor};

        next if ( $vendor_ref->{'installed'} == 0 );

        my $output;

        my $vendor_url = $vendor_ref->{'installed_from'};
        my $vendor_id  = $vendor_ref->{'vendor_id'};

        my $enabled = $vendor_ref->{'enabled'};

        next if !defined $vendor_url || !defined $vendor_url || !defined $enabled;

        $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'add', $vendor_url );
        if ($enabled) {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'enable', $vendor_id );
        }
        else {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'disable', $vendor_id );
        }

        my $update = $vendor_ref->{'update'};
        $update = 0 if ( !defined $update );

        if ($update) {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'enable-updates', $vendor_id );
        }
        else {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'disable-updates', $vendor_id );
        }

        my $configs = $vendor_ref->{'configs'};
        $configs = 1 if ( defined $configs );
        $configs = 0 if ( !defined $configs );

        if ($configs) {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'enable-configs', $vendor_id );
            if ( $enabled && $configs && exists $vendor_ref->{'rules'} ) {
                my @configs = keys %{ $vendor_ref->{'rules'} };

                foreach my $config (@configs) {
                    my $args     = { 'config' => $config };
                    my $metadata = {};

                    # problems in modsec_make_config_active causes very ugly screen errors.
                    # we do not care if there are errors we are just trying to do a best
                    # effort.
                    eval {
                        if ( $vendor_ref->{'rules'}->{$config}->{'config_active'} eq "1" ) {
                            Whostmgr::API::1::ModSecurity::modsec_make_config_active( $args, $metadata );
                        }
                        else {
                            Whostmgr::API::1::ModSecurity::modsec_make_config_inactive( $args, $metadata );
                        }
                    };
                }
            }
        }
        else {
            $output = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'disable-configs', $vendor_id );
        }
    }

    return;
}

sub loadModsecSettings {
    my ($self) = @_;

    return if ( !exists $self->{'modsec_settings'} );

    my $modsec_settings = $self->{'modsec_settings'};

    foreach my $idx ( 0 .. ( @{$modsec_settings} - 1 ) ) {
        my $settings_ref = $modsec_settings->[$idx];

        my @results;

        try {
            if ( $settings_ref->{'state'} eq "" ) {
                @results = Whostmgr::ModSecurity::Settings::remove_setting( $settings_ref->{'setting_id'} );
            }
            else {
                @results = Whostmgr::ModSecurity::Settings::set_setting( $settings_ref->{'setting_id'}, $settings_ref->{'state'} );
            }
        }
        catch {
            warn "Failed to adjust ModSecurity setting with ID $settings_ref->{'setting_id'}: $_";
        };
    }

    if (@$modsec_settings) {
        try {
            Whostmgr::ModSecurity::Settings::deploy_settings_changes();
        }
        catch {
            warn "Failed to deploy new ModSecurity configuration settings: $_";
        };
    }

    return;
}

sub loadPipedLogConfig {
    my ($self) = @_;

    # get out quickly if we do not need to change the setting

    my $cpconf_guard;
    $cpconf_guard ||= Cpanel::Config::CpConfGuard->new();

    return ( 1, "Successful" ) if !defined $cpconf_guard->{'data'}->{'enable_piped_logs'};    # was not in the source tweak settings?
    if ( defined( $self->{'enable_piped_logs'} ) ) {
        return ( 1, "Successful" ) if $cpconf_guard->{'data'}->{'enable_piped_logs'} == $self->{'enable_piped_logs'};
    }

    # we need to change the piped logs on this server
    # this code is mostly copied from whosmgr2::_change_piped_logs

    if ( $self->{'enable_piped_logs'} ) {
        if ( -x '/usr/local/cpanel/bin/splitlogs' && Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/bin/splitlogs', '--bincheck' ) =~ /BinCheck Ok/ ) {
            $cpconf_guard->{'data'}->{'enable_piped_logs'} = 1;
        }
        else {
            return ( 0, 'Splitlogs program failed execution test. Piped logging was not enabled.' );
        }
    }
    else {
        $cpconf_guard->{'data'}->{'enable_piped_logs'} = 0;
    }

    $cpconf_guard->save();
    my $output = Cpanel::SafeRun::Errors::saferunallerrors('/usr/local/cpanel/bin/build_apache_conf');
    if ( $output !~ /OK$/ ) {
        return ( 0, "Unable to update Apache configuration: $output" );
    }
    my ( $status, $message ) = Cpanel::HttpUtils::ApRestart::safeaprestart(0);

    if ( !$status ) {
        return ( 0, $message );
    }

    require Cpanel::Signal;
    Cpanel::Signal::send_hup_cpanellogd();
    return ( 1, "Log Processing Application (cpanellogd) Reloaded." );
}

sub post_restore {
    my ($self) = @_;

    # rules to consider
    #
    # Destination is EA3
    #
    # GIVEN the source server has EA3
    # WHEN the destination server has EA3
    # THEN the new profile should be installed
    #
    # GIVEN the source server has EA4
    # WHEN the destination server has EA3
    # THEN we should convert the destination server to EA4
    #
    # Destination is EA4
    #
    # GIVEN the source server has EA4
    # WHEN the destination server has EA4
    # THEN the user's profile should be restored via EA4
    #
    # GIVEN the source server has EA3
    # WHEN the destination server has EA4
    # THEN we should convert their EA3 profile to an EA4 profile and install it
    #

    # Destination is EA3 (or --skip-webserver)
    if ( !$self->{'target_is_ea4'} ) {
        return ( 0, "Can’t restore to a non-EA4 machine" );
    }
    else {
        # Destination is EA4

        if ( !$self->{'source_is_ea4'} ) {

            # Source is EA3
            return ( 0, "Can not restore EA3 on an EA4 server. You must migrate from EA3 to EA4 on v76 and then back/restore that. You can do so by running /usr/local/cpanel/scripts/migrate_ea3_to_ea4 or via WHM’s EasyApache 4 Migration interface. For more information please see: https://go.cpanel.net/EA4Migration" );
        }
        else {
            # Source is EA4
            #

            # instead of marking an error and leaving
            # install cpanel default profile
            # add this message though

            my $msg     = "";
            my $default = "/etc/cpanel/ea4/profiles/cpanel/default.json";

            my $profile_file = Whostmgr::Config::Apache::get_current_profile_file();

            if ( !-e Whostmgr::Config::Apache::get_current_profile_file() ) {
                $msg .= "Source profile is missing... using default profile.";
                $profile_file = $default;
            }

            Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/bin/ea_install_profile', '--install', $profile_file );

            Cpanel::HttpUtils::ApRestart::safeaprestart();
            return ( 0, "Apache did not restart." ) if !Cpanel::HttpUtils::ApRestart::httpd_is_running();

            $self->loadModsecVendors();
            $self->loadModsecSettings();

            my ( $status, $status_msg ) = $self->loadPipedLogConfig();
            return ( 0, $status_msg ) if $status < 1;

            $msg = "EA4 profile installed." if ( !length($msg) );

            return ( 1, $msg );
        }
    }
}

1;
