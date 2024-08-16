package Cpanel::GreyList::Config;

# cpanel - Cpanel/GreyList/Config.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my $CONF_DIR              = '/var/cpanel/greylist';
my $PID_FILE              = '/var/run/cpgreylistd.pid';
my $SOCKET_PATH           = '/var/run/cpgreylistd.sock';
my $SQLITE_DB             = $CONF_DIR . '/greylist.sqlite';
my $ENABLE_FILE           = $CONF_DIR . '/enabled';
my $CONF_FILE             = $CONF_DIR . '/conf';
my $COMMON_MAIL_CONF_FILE = $CONF_DIR . '/common_mail_providers_conf';

my $LOGFILE_PATH = '/usr/local/cpanel/logs/cpgreylistd.log';

use constant DEFAULT => {
    'initial_block_time_mins' => 5,              # 5 mins
    'must_try_time_mins'      => 4 * 60,         # 4 hrs
    'record_exp_time_mins'    => 3 * 24 * 60,    # 3 days
    'spf_bypass'              => 0,              # Skip greylisting if SPF check passes
    'purge_interval_mins'     => 60,             # 1 hr
    'child_timeout_secs'      => 5,              # 5 seconds
    'max_child_procs'         => 5,              # max number of children the daemon will fork to process requests
};

#----------------------------------------------------------------------

sub get_conf_dir              { return $CONF_DIR; }
sub get_pid_file              { return $PID_FILE; }
sub get_socket_path           { return $SOCKET_PATH; }
sub get_sqlite_db             { return $SQLITE_DB; }
sub get_conf_file             { return $CONF_FILE; }
sub get_common_mail_conf_file { return $COMMON_MAIL_CONF_FILE; }
sub get_logfile_path          { return $LOGFILE_PATH; }
sub get_enable_file           { return $ENABLE_FILE; }

sub get_purge_interval_mins { return loadconfig()->{'purge_interval_mins'}; }
sub get_child_timeout_secs  { return loadconfig()->{'child_timeout_secs'}; }
sub get_max_child_procs     { return loadconfig()->{'max_child_procs'}; }

sub is_enabled { return -e get_enable_file() ? 1 : 0 }

sub enable {
    if ( !-d get_conf_dir() ) {
        require File::Path;
        File::Path::make_path( get_conf_dir() );
    }

    require Cpanel::FileUtils::TouchFile;
    Cpanel::FileUtils::TouchFile::touchfile( get_enable_file() );
    return 1;
}

sub disable {
    if ( -e get_enable_file() ) {
        unlink( get_enable_file() ) && return 1;
        return;
    }
    return 1;
}

# NB: This loads ONLY the information on whether providers are set to
# auto-update. The information about whether an individual provider is
# trusted or not comes from get_common_mail_providers() … which you have
# to call anyway to call into this function because the expected input is
# a lookup hash of provider names, e.g., “symantec_messagelabs”.
#
# For a simple way to get the entire configuration matrix for common mail
# providers, look at Cpanel::GreyList::CommonMailProviders::Config.
#
sub load_common_mail_providers_config {
    my $default_config_hr = shift;
    die Cpanel::Exception->create('The default common mail provider configuration is not set.') if !$default_config_hr || ref $default_config_hr ne 'HASH';

    # By default, we want to automatically trust any new mail providers that cPanel adds to the list.
    $default_config_hr->{'autotrust_new_common_mail_providers'} = 1;

    _any_loadConfig( get_common_mail_conf_file(), $default_config_hr );

    return $default_config_hr;
}

sub save_common_mail_providers_config {
    my ( $default_config_hr, $new_config_hr ) = @_;

    my $valid_mail_providers = { %{$default_config_hr} };
    my $config_hr            = load_common_mail_providers_config($default_config_hr);

    my $is_boolean = sub { return 1 if ( defined $_[0] && ( $_[0] eq '1' || $_[0] eq '0' ) ); return; };
    foreach my $key ( keys %{$new_config_hr} ) {
        exists $config_hr->{$key}               or die Cpanel::Exception->create( "Invalid configuration option: “[_1]” is not a supported common mail provider.", [$key] );
        $is_boolean->( $new_config_hr->{$key} ) or die Cpanel::Exception->create( "Invalid configuration value: “[_1]” for “[_2]”.",                               [ $new_config_hr->{$key}, $key ] );
    }

    foreach my $key ( keys %{$config_hr} ) {
        next if not exists $valid_mail_providers->{$key} && $key ne 'autotrust_new_common_mail_providers';
        if ( !exists $new_config_hr->{$key} || !defined $new_config_hr->{$key} ) {
            $new_config_hr->{$key} = $config_hr->{$key};
        }
    }

    require Cpanel::Config::FlushConfig;
    Cpanel::Config::FlushConfig::flushConfig( get_common_mail_conf_file(), $new_config_hr, undef, undef, { 'perms' => 0600 } ) or die Cpanel::Exception->create( "Failed to save configuration file: [_1]", [$!] );
    return 1;
}

our $_conf_cache_ref;

sub loadconfig {

    my $config = { %{ DEFAULT() } };

    my $filesys_mtime = 0;
    if ( -e get_conf_file() ) {
        $filesys_mtime = ( stat(_) )[9];
    }

    if ( $_conf_cache_ref && exists $_conf_cache_ref->{'mtime'} && $filesys_mtime == $_conf_cache_ref->{'mtime'} ) {
        return $_conf_cache_ref->{'conf'};
    }

    _any_loadConfig( get_conf_file(), $config );
    $config->{'is_enabled'} = is_enabled() . "";

    $_conf_cache_ref = { 'mtime' => $filesys_mtime, 'conf' => $config };

    return $config;
}

sub saveconfig {
    my $new_config_hr = shift || {};
    my $old_config_hr = loadconfig();

    my $is_positive_int            = sub { return 1 if ( $_[0] && $_[0] =~ m/^\d+$/ );                        return; };
    my $is_digit_and_less_than_max = sub { return 1 if ( $_[0] && $_[0] =~ m/^\d+$/ && $_[0] <= $_[1] );      return; };
    my $is_boolean                 = sub { return 1 if ( defined $_[0] && ( $_[0] eq '1' || $_[0] eq '0' ) ); return; };

    require Cpanel::Locale;
    require Cpanel::Exception;
    require Cpanel::Config::FlushConfig;
    my $locale         = Cpanel::Locale->get_handle();
    my $config_options = {
        'initial_block_time_mins' => {
            'validation' => $is_digit_and_less_than_max,
            'desc'       => $locale->maketext('Initial Deferral Period'),
            'max'        => 4 * 60,                                         # 4 hrs
        },
        'must_try_time_mins' => {
            'validation' => $is_digit_and_less_than_max,
            'desc'       => $locale->maketext('Resend Acceptance Period'),
            'max'        => 24 * 60,                                         # 24 hrs
        },
        'record_exp_time_mins' => {
            'validation' => $is_digit_and_less_than_max,
            'desc'       => $locale->maketext('Record Expiration Time'),
            'max'        => 30 * 24 * 60,                                    # 30 days
        },
        'spf_bypass' => {
            'validation' => $is_boolean,
            'desc'       => $locale->maketext('Bypass [asis,Greylisting] for Hosts with Valid [output,acronym,SPF,Sender Policy Framework] Records'),
        },
        'purge_interval_mins' => {
            'validation' => $is_positive_int,
            'desc'       => $locale->maketext('Record Purge Interval'),
        },
        'child_timeout_secs' => {
            'validation' => $is_positive_int,
            'desc'       => $locale->maketext('Child process time-out.'),
        },
        'max_child_procs' => {
            'validation' => $is_positive_int,
            'desc'       => $locale->maketext('Maximum number of processes the [asis,GreyListing] daemon can create.'),
        },
    };

    foreach my $key ( keys %{$new_config_hr} ) {
        if (   exists $config_options->{$key}
            && exists $config_options->{$key}->{'validation'}
            && !$config_options->{$key}->{'validation'}->( $new_config_hr->{$key}, $config_options->{$key}->{'max'} ) ) {
            die Cpanel::Exception->create(
                "Invalid configuration value, “[_1]” for “[_2]” (max: [_3]).",
                [ $new_config_hr->{$key}, $config_options->{$key}->{'desc'}, ( $config_options->{$key}->{'max'} || 'n/a' ) ]
            );
        }
    }
    foreach my $key ( keys %{$config_options} ) {
        if ( !exists $new_config_hr->{$key} || !defined $new_config_hr->{$key} ) {
            $new_config_hr->{$key} = $old_config_hr->{$key};
        }
    }
    delete $new_config_hr->{'is_enabled'};

    if ( $new_config_hr->{'initial_block_time_mins'} >= $new_config_hr->{'must_try_time_mins'} ) {
        die Cpanel::Exception->create(
            "Invalid configuration value, “[_1]” cannot be greater than or equal to the “[_2]” value: [_3]",
            [ $config_options->{'initial_block_time_mins'}->{'desc'}, $config_options->{'must_try_time_mins'}->{'desc'}, $new_config_hr->{'must_try_time_mins'} ]
        );
    }
    elsif ( $new_config_hr->{'initial_block_time_mins'} >= $new_config_hr->{'record_exp_time_mins'} ) {
        die Cpanel::Exception->create(
            "Invalid configuration value, “[_1]” cannot be greater than or equal to the “[_2]” value: [_3]",
            [ $config_options->{'initial_block_time_mins'}->{'desc'}, $config_options->{'record_exp_time_mins'}->{'desc'}, $new_config_hr->{'record_exp_time_mins'} ]
        );
    }
    elsif ( $new_config_hr->{'must_try_time_mins'} >= $new_config_hr->{'record_exp_time_mins'} ) {
        die Cpanel::Exception->create(
            "Invalid configuration value, “[_1]” cannot be greater than or equal to the “[_2]” value: [_3]",
            [ $config_options->{'must_try_time_mins'}->{'desc'}, $config_options->{'record_exp_time_mins'}->{'desc'}, $new_config_hr->{'record_exp_time_mins'} ]
        );
    }

    Cpanel::Config::FlushConfig::flushConfig( get_conf_file(), $new_config_hr, undef, undef, { 'perms' => 0600 } ) or die Cpanel::Exception->create( "Failed to save configuration file: [_1]", [$!] );
    return 1;
}

sub _any_loadConfig {
    if ( $INC{'Cpanel/Config/LoadConfig.pm'} ) {
        goto \&Cpanel::Config::LoadConfig::loadConfig;
    }
    require Cpanel::Config::LoadConfig::Tiny;
    goto \&Cpanel::Config::LoadConfig::Tiny::loadConfig;
}

1;
