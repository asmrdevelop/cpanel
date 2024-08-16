package Whostmgr::Config::Backup::Easy::Apache;

# cpanel - Whostmgr/Config/Backup/Easy/Apache.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Backup::Base );

use Cpanel::SafeRun::Errors ();
use Cpanel::TempFile        ();
use Cpanel::JSON            ();

use Whostmgr::Config::BackupUtils ();
use Whostmgr::Config::Backup      ();
use Whostmgr::Config::Apache      ();

use Whostmgr::API::1::ModSecurity   ();
use Whostmgr::ModSecurity::Settings ();

use Try::Tiny;

use constant version => '1.0.0';

sub parse_modsec_vendor {
    my ($modsec_vendor_output) = @_;

    my @lines      = split( /\n/, $modsec_vendor_output );
    my $output_ref = {};
    my $ref        = {};

    foreach my $line (@lines) {
        if ( $line =~ m/^ *([a-zA-Z0-9_]+) \| (.+)$/ ) {
            $ref->{$1} = $2;
        }
        else {
            if ( exists $ref->{'name'} ) {
                $output_ref->{ $ref->{'name'} } = $ref;
                $ref = {};
            }
            else {
                $ref = {};
            }
        }
    }

    if ( exists $ref->{'name'} ) {
        $output_ref->{ $ref->{'name'} } = $ref;
        $ref = {};
    }

    return $output_ref;
}

our $ea3_modsec2_user_conf_path = '/usr/local/apache/conf/modsec2.user.conf';
our $ea4_modsec2_user_conf_path = '/etc/apache2/conf.d/modsec2.user.conf';

our $var_cpanel_conf_apache = '/var/cpanel/conf/apache';
our $usr_local_apache_conf  = '/usr/local/apache/conf';
our $var_cpanel_templates   = '/var/cpanel/templates';
our $var_cpanel             = '/var/cpanel';

sub _backup {
    my $self   = shift;
    my $parent = shift;

    my $files_to_copy = $parent->{'files_to_copy'}->{'cpanel::easy::apache'} = {};
    my $dirs_to_copy  = $parent->{'dirs_to_copy'}->{'cpanel::easy::apache'}  = {};

    # jump through hoops for Modsec

    my $output     = Cpanel::SafeRun::Errors::saferunallerrors( '/usr/local/cpanel/scripts/modsec_vendor', 'list' );
    my $modsec_ref = parse_modsec_vendor($output);

    # now get the statuses of the invidual rules

    my @vendor_keys = keys %{$modsec_ref};
    foreach my $vendor_key (@vendor_keys) {
        my $vendor_id = $modsec_ref->{$vendor_key}->{'vendor_id'};

        my $args = {
            'vendor_id' => $vendor_id,
        };

        my $metadata = {};

        # problems in modsec_get_rules causes very ugly screen errors.
        # we do not care if there are errors we are just trying to do a best
        # effort.
        eval {
            my $ref   = Whostmgr::API::1::ModSecurity::modsec_get_rules( $args, $metadata );
            my $rules = {};

            foreach my $chunk ( @{ $ref->{'chunks'} } ) {
                $rules->{ $chunk->{'config'} } = { 'config_active' => $chunk->{'config_active'} };
            }

            $modsec_ref->{$vendor_key}->{'rules'} = $rules;
        };
    }

    $self->{'temp_obj'} = Cpanel::TempFile->new();
    my $temp_dir = $self->{'temp_dir'} = $self->{'temp_obj'}->dir();

    my $modsec_vendor_json = "$temp_dir/modsec_vendor.json";
    my $pretty_json        = Cpanel::JSON::pretty_dump($modsec_ref);

    if ( open( my $modsec_fh, '>', $modsec_vendor_json ) ) {
        print {$modsec_fh} $pretty_json;
        close $modsec_fh;
    }

    $files_to_copy->{$modsec_vendor_json} = { "dir" => "cpanel/easy/apache" };

    # do a modsec get_settings so I can carry them over to the restore system

    my $modsec_settings_json = "$temp_dir/modsec_settings.json";
    my $modsec_settings_ref;

    # get_settings() is set to die if it cannot determine modsec version.
    # trapping this die here will allow us to continue with the EA transfer
    # even if modsec is not installed on the remote server.
    try {
        $modsec_settings_ref = Whostmgr::ModSecurity::Settings::get_settings();
    }
    catch {
        $modsec_settings_ref = {} if $_;
    };

    $pretty_json = Cpanel::JSON::pretty_dump($modsec_settings_ref);

    if ( open( my $modsec_fh, '>', $modsec_settings_json ) ) {
        print {$modsec_fh} $pretty_json;
        close $modsec_fh;
    }

    $files_to_copy->{$modsec_settings_json} = { "dir" => "cpanel/easy/apache" };

    # Our policy regarding modsec2.user.conf is to bring it over along with
    # the files referenced in any of the include statements, but we will
    # not restore them.

    my $modsec2_user_conf = $ea4_modsec2_user_conf_path;
    $modsec2_user_conf = $ea3_modsec2_user_conf_path if ( !-e $modsec2_user_conf );

    if ( -e $modsec2_user_conf && ( -s $modsec2_user_conf ) )    # modsec2.user.conf often exists but is empty
    {
        require Cpanel::Slurper;

        my $content = Cpanel::Slurper::read($modsec2_user_conf);

        my @lines = split( /\n/, $content );
        foreach (@lines) {
            if (m/^\s*include\s+[\'\"]?([\/\w\.\-0-9]+)[\'\"]?\s*$/i) {
                my $filename = $1;
                my $path     = Whostmgr::Config::BackupUtils::get_parent_path( $filename, 0 );
                $files_to_copy->{$filename} = { "dir" => "cpanel/easy/apache/modsec2_user_conf_files" . $path };
            }
        }
    }

    # if we are EA4 then get a snapshot of the current profile
    Whostmgr::Config::Apache::create_current_profile();

    foreach my $cfg_file ( keys %Whostmgr::Config::Apache::apache_files ) {
        my $cfg = $Whostmgr::Config::Apache::apache_files{$cfg_file};

        my $special = $cfg->{'special'};
        if ( $special eq "dir" ) {
            next if !-e $cfg_file;
            my $archive_dir = $cfg->{'archive_dir'};
            $dirs_to_copy->{$cfg_file} = { "archive_dir" => $archive_dir };
        }
        elsif ( $special =~ m/(present|archive)/ ) {
            next if !-e $cfg_file;
            my $dir = "cpanel/easy/apache/config";
            $dir = $cfg->{'archive_dir'} if exists $cfg->{'archive_dir'};
            $files_to_copy->{$cfg_file} = { "dir" => $dir };
        }
    }

    # I am going to separate these files off because they are hit
    # or miss as to whether they exist or not

    Whostmgr::Config::Backup::backup_ifexists( $parent, 'cpanel::easy::apache', $var_cpanel_conf_apache, 'cpanel/easy/apache/other',         'local' );
    Whostmgr::Config::Backup::backup_ifexists( $parent, 'cpanel::easy::apache', $var_cpanel_conf_apache, 'cpanel/easy/apache/other',         'main' );
    Whostmgr::Config::Backup::backup_ifexists( $parent, 'cpanel::easy::apache', $usr_local_apache_conf,  'cpanel/easy/apache/conf_includes', 'includes' );
    Whostmgr::Config::Backup::backup_ifexists( $parent, 'cpanel::easy::apache', $var_cpanel_templates,   'cpanel/easy/apache/templates',     "apache*/*local" );
    Whostmgr::Config::Backup::backup_ifexists( $parent, 'cpanel::easy::apache', $var_cpanel,             'cpanel/easy/apache/tweak',         'cpanel.config' );

    return ( 1, __PACKAGE__ . ": ok" );
}

sub post_backup {
    my ($self) = @_;

    delete $self->{'temp_obj'};    # will rm -rf the dir
    return;
}

sub query_module_info {
    my %output = ( EAVERSION => 'EA4' );

    require Cpanel::ConfigFiles::Apache::modules;

    # Get the local version
    my $local_apache_version = Cpanel::ConfigFiles::Apache::modules::apache_long_version();
    $output{'HTTPDVERSION'} = $local_apache_version;

    return \%output;
}

1;
