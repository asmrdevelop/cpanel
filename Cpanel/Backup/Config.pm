package Cpanel::Backup::Config;

# cpanel - Cpanel/Backup/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug           ();
use Cpanel::CachedDataStore ();
use Cpanel::Config::Backup  ();
use Cpanel::LoadModule      ();
use Cpanel::Config::Users   ();
use Cpanel::Config::LoadCpUserFile();
use Cpanel::SafeDir::MK ();
use Cpanel::ConfigFiles ();

our $config_path = $Cpanel::ConfigFiles::backup_config;
my $locale;

# This hash contains the different datatypes and values for different values
# Data type explanation:
#
# abnormal - yes/no string boolean
# string - a string, any string
# bool - 0 or 1 boolean value
#

# If you update this hash’s keys be sure to reflect those changes in the 'backup_config_set' hash’s 'args' in whostmgr/bin/xml-api.pl
my $config_spec = {
    'LOCALZONESONLY' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'BACKUPACCTS' => {
        'type'    => 'abnormal',
        'default' => 'yes'
    },
    'BACKUPSUSPENDEDACCTS' => {
        'type'    => 'abnormal',
        'default' => 'no'
    },
    'BACKUPBWDATA' => {
        'type'    => 'abnormal',
        'default' => 'yes',
    },
    'BACKUPDAYS' => {
        'type'    => 'string',
        'default' => '0,2,4,6',
        'valid'   => sub {
            my ($value) = @_;
            return 1 if $value =~ /^[0-6](,[0-6]){0,6},?$/;
            return 0;
        }
    },
    'BACKUP_WEEKLY_DAY' => {
        'type'    => 'string',
        'default' => 0,
        'valid'   => _numeric_range_validation( min => 0, max => 6 )
    },
    'BACKUP_MONTHLY_DATES' => {
        'type'    => 'string',
        'default' => '1',
        'valid'   => sub {
            my ($value) = @_;
            return 0 if $value !~ /^\d{1,2}/;
            my @nums = split( /\,/, $value );

            my $validate = _numeric_range_validation( min => 1, max => 31 );
            foreach my $num (@nums) {
                return 0 unless $validate->($num);
            }
            return 1;
        }
    },
    'BACKUPDIR' => {
        'type'    => 'string',
        'default' => '/backup',
    },
    'BACKUPENABLE' => {
        'type'    => 'abnormal',
        'default' => 'no'
    },
    'BACKUP_DAILY_ENABLE' => {
        'type'    => 'abnormal',
        'default' => 'yes'
    },
    'BACKUP_WEEKLY_ENABLE' => {
        'type'    => 'abnormal',
        'default' => 'no'
    },
    'BACKUP_MONTHLY_ENABLE' => {
        'type'    => 'abnormal',
        'default' => 'no'
    },
    'BACKUPFILES' => {
        'type'    => 'abnormal',
        'default' => 'yes',
    },
    'BACKUP_DAILY_RETENTION' => {
        'type'    => 'string',
        'default' => 5,
        'valid'   => _numeric_range_validation( min => 1, max => 9_999 )
    },
    'BACKUP_WEEKLY_RETENTION' => {
        'type'    => 'string',
        'default' => 4,
        'valid'   => _numeric_range_validation( min => 1, max => 9_999 )
    },
    'BACKUP_MONTHLY_RETENTION' => {
        'type'    => 'int',
        'default' => 1,
        'valid'   => _numeric_range_validation( min => 1, max => 9_999 )
    },
    'KEEPLOCAL' => {
        'type'    => 'bool',
        'default' => 1,
    },
    'BACKUPLOGS' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'BACKUPMOUNT' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'BACKUPTYPE' => {
        'type'    => 'string',
        'default' => 'compressed',
        'valid'   => [ 'compressed', 'uncompressed', 'incremental' ],
    },
    'GZIPRSYNCOPTS' => {
        'type'    => 'string',
        'default' => '',
    },
    'MAXIMUM_TIMEOUT' => {
        'type'    => 'int',
        'default' => 7_200,
        'valid'   => _numeric_range_validation( min => 300, max => 50_000 )
    },
    'MAXIMUM_RESTORE_TIMEOUT' => {
        'type'    => 'int',
        'default' => 21_600,
        'valid'   => _numeric_range_validation( min => 600, max => 86_400 )
    },
    'MYSQLBACKUP' => {
        'type'    => 'string',
        'default' => 'accounts',
        'valid'   => [ 'accounts', 'both', 'dir' ],
    },
    'POSTBACKUP' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'PREBACKUP' => {
        'type'    => 'string',
        'default' => '-1',
    },
    'PSQLBACKUP' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'ERRORTHRESHHOLD' => {
        'type'    => 'int',
        'default' => 3,
    },
    'LINKDEST' => {
        'type'    => 'bool',
        'default' => 0,
    },
    'CHECK_MIN_FREE_SPACE' => {
        'type'    => 'bool',
        'default' => '1',
    },
    'MIN_FREE_SPACE' => {
        'type'    => 'int',
        'default' => 5,
        'valid'   => _numeric_range_validation( min => 0 ),

        # There isn't a mechanism for checking MIN_FREE_SPACE_UNIT at this
        # point; if the unit is 'percent', this value cannot exceed 100,
        # but if 'MB', it likely *will*. That check will have to happen
        # elsewhere.
    },
    'MIN_FREE_SPACE_UNIT' => {
        'type'    => 'string',
        'default' => 'percent',
        'valid'   => [ 'percent', 'MB' ],
    },
    'FORCE_PRUNE_DAILY' => {
        'type'    => 'bool',
        'default' => 0,
    },
    'FORCE_PRUNE_WEEKLY' => {
        'type'    => 'bool',
        'default' => 0,
    },
    'FORCE_PRUNE_MONTHLY' => {
        'type'    => 'bool',
        'default' => 0,
    },
    'DISABLE_METADATA' => {
        'type'    => 'abnormal',
        'default' => 'no',
    },
    'REMOTE_RESTORE_STAGING_DIR' => {
        'type'    => 'string',
        'default' => '/backup',
    },
};

sub _numeric_range_validation {
    my (%opts) = @_;
    return sub {
        my $value = shift;
        no warnings 'numeric';
        return 0 if ( int($value) != $value );
        return 0 if defined $opts{min} && $value < $opts{min};
        return 0 if defined $opts{max} && $value > $opts{max};
        return 1;
    };
}

# get 'yes' and 'no' values as 1s and 0s (used in the API)
sub get_normalized_config {
    my $config = load();
    my %new_config;
    foreach my $key ( keys %{$config} ) {
        my $lc_key = lc $key;
        next unless $config_spec->{$key};    # Ignore unknown config options
        if ( $config_spec->{$key}->{'type'} eq 'abnormal' ) {
            if ( $config->{$key} eq 'yes' ) {
                $new_config{$lc_key} = 1;
            }
            elsif ( $config->{$key} eq 'no' ) {
                $new_config{$lc_key} = 0;
            }
        }
        else {
            $new_config{$lc_key} = $config->{$key};
        }
    }
    return \%new_config;
}

my $backup_dirs_cache;

# Get the backup dirs from both the old and the new systems
sub get_backup_dirs {
    my @dirs = ();

    if ( $backup_dirs_cache && $backup_dirs_cache->[0] + 10 > time() ) {
        return $backup_dirs_cache->[1];
    }

    # get old
    my $legacy_backup_dir = '';
    my $legacy_conf       = Cpanel::Config::Backup::load();
    if ( $legacy_conf->{'BACKUPENABLE'} eq 'yes' ) {

        $legacy_backup_dir = Cpanel::Config::Backup::get_backupdir();
        if ( length $legacy_backup_dir && -d $legacy_backup_dir ) {
            my ( $ret, $msg ) = verify_backupdir($legacy_backup_dir);
            if ( $ret == 1 ) {
                push @dirs, $legacy_backup_dir;
            }
            else {
                Cpanel::Debug::log_info("Invalid legacy backup directory \"$legacy_backup_dir\": $msg");
            }
        }
    }

    # get new
    my $conf = load();
    if ( $conf->{'BACKUPENABLE'} eq 'yes' ) {

        my $backup_dir = $conf->{'BACKUPDIR'};

        # no need for a duplicate directory
        if ( !length $legacy_backup_dir || $legacy_backup_dir ne $backup_dir ) {
            if ( -d $backup_dir ) {
                my ( $ret, $msg ) = verify_backupdir($backup_dir);
                if ( $ret == 1 ) {
                    push @dirs, $backup_dir;
                }
                else {
                    Cpanel::Debug::log_info("Invalid legacy backup directory \"$legacy_backup_dir\": $msg");
                }
            }
        }
    }

    $backup_dirs_cache = [ time(), \@dirs ];

    return \@dirs;
}

sub clear_backup_dirs_cache {
    $backup_dirs_cache = undef;
    return;
}

sub load {
    my $result = _get_default_values();

    if ( -e _get_config_path() ) {
        my $config = Cpanel::CachedDataStore::fetch_ref( _get_config_path() );

        # Write what we loaded over the default values,
        # This will give us the default for each one which is missing
        @{$result}{ keys %$config } = values %$config;
    }

    return $result;
}

sub _get_default_values {
    my $values = {};
    foreach my $key ( keys %{$config_spec} ) {
        $values->{$key} = $config_spec->{$key}->{'default'};
    }
    return $values;
}

sub save {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($new_save_data_ref) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SafeFile');
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    $locale ||= Cpanel::Locale->get_handle();
    my $config = load();

    # We expect all the keys for the data to be lower case,
    # so we will convert them all here to remove any ambiguity
    my %lc_new_data  = map { lc $_ => $new_save_data_ref->{$_} } keys %$new_save_data_ref;
    my $new_data_ref = \%lc_new_data;

    # Currently we do not care to disable the cron job
    # If we are enabling backups from a disabled state, be sure to add the cron job
    if ( exists $new_data_ref->{'backupenable'} and $new_data_ref->{'backupenable'} =~ m/^y|^1/ and $config->{'BACKUPENABLE'} eq 'no' ) {
        Cpanel::Debug::log_debug("Turning on cronjob");
        if ( Cpanel::Config::Backup::add_cronjob() ) {
            Cpanel::Debug::log_debug("Cronjob set with success.");
        }
    }

    # Fill this with keys holding any values found to be invalid
    my @invalid_fields;

    # Perform hash merge, populate default values
    foreach my $key ( keys %{$config_spec} ) {

        # handle either upper or lower case keys
        if ( exists $new_data_ref->{ lc $key } || exists $new_data_ref->{ uc $key } || exists $new_data_ref->{$key} ) {

            my $value;
            if ( exists $new_data_ref->{ lc $key } ) {
                $value = $new_data_ref->{ lc $key };
            }
            elsif ( exists $new_data_ref->{ uc $key } ) {
                $value = $new_data_ref->{ uc $key };
            }
            else {
                $value = $new_data_ref->{ uc $key };
            }

            # Abnormalize normal values (convert 1/on and 0/off to 'yes' and 'no')
            if ( $config_spec->{$key}->{'type'} eq 'abnormal' ) {
                if ( $value eq '1' or $value =~ /^on$/i ) {
                    $value = 'yes';
                }
                elsif ( $value eq '0' or $value =~ /^off$/i ) {
                    $value = 'no';
                }
            }

            # Validate values before merging
            if ( validator( $key, $value ) ) {
                $config->{$key} = $value;
            }
            else {
                push @invalid_fields, $key;
            }
        }
        elsif ( exists $config->{$key} ) {

            # do nothing as we're modifying the in-place hash
        }
        else {

            # if it does not exist in new_data_ref nor in the stored config
            # then load the default value
            $config->{$key} = $config_spec->{$key}->{'default'};
        }
    }

    # If we're checking disk space for backups, and we've tried to set
    # the available disk space value to something nonsensical, deal
    # with that here. (We've already checked for below-zero values in the
    # validator!)
    if ( $config->{'CHECK_MIN_FREE_SPACE'} && $config->{'MIN_FREE_SPACE_UNIT'} eq 'percent' && $config->{'MIN_FREE_SPACE'} > 100 ) {
        return ( 0, $locale->maketext("If the min_free_space_unit is “percent”, then the min_free_space parameter must be 100 or less.") );
    }

    # Make sure that we have some place to back up if backups are enabled.
    my $enabled = $config->{'BACKUPENABLE'} && $config->{'BACKUPENABLE'} eq "yes";
    if ( $enabled && !$config->{'KEEPLOCAL'} ) {
        Cpanel::LoadModule::load_perl_module('Cpanel::Backup::Transport');
        my $transport = Cpanel::Backup::Transport->new();
        if ( !scalar keys %{ $transport->get_enabled_destinations() } ) {
            return ( 0, $locale->maketext("Nowhere to back up: no enabled destinations found and retaining local copies is disabled.") );
        }
    }

    # Validate the backup directory and create it if it doesn't exist
    # only allow absolute paths, don't allow obviously bad destinations common to most all systems

    foreach my $cfg_dir ( 'BACKUPDIR', 'REMOTE_RESTORE_STAGING_DIR' ) {
        my ( $retvalue, $msg ) = verify_backupdir( $config->{$cfg_dir}, $cfg_dir );
        if ( $retvalue != 1 ) {
            return ( 0, $msg );
        }

        if ( !-e $config->{$cfg_dir} ) {
            eval {

                # Don't throw an error if this fails, we'll test for and return an error
                Cpanel::SafeDir::MK::safemkdir( $config->{$cfg_dir}, 0711 );
            };
        }

        # If we couldn't create it as a directory, then validation for this has failed
        if ( !-d $config->{$cfg_dir} ) {
            push @invalid_fields, $cfg_dir;
        }
    }

    # If any values were invalid, return this to the caller
    if ( scalar @invalid_fields > 0 ) {
        return ( 0, $locale->maketext( 'Invalid value for: [list_and,_1]', \@invalid_fields ) );
    }

    # check to see if we are using incremental backups and if so, does the path support hard links
    if ( exists $new_data_ref->{'backuptype'} and $new_data_ref->{'backuptype'} eq 'incremental' ) {
        Cpanel::Debug::log_debug("Incremental backups selected");
        my ( $ret, $msg ) = hardlinks_supported( $new_data_ref->{'backupdir'} );
        if ( $ret == 1 ) {
            Cpanel::Debug::log_debug("Incremental backup directory supports hard links");
        }
        else {
            Cpanel::Debug::log_info("Incremental backup directory does not support hard links : $msg");
            return ( 0, $msg );
        }
    }

    my $config_path = _get_config_path();

    my $lock = Cpanel::SafeFile::safelock($config_path);

    if ( !$lock ) {
        return ( 0, 'Unable to save config file since the file could not be locked.' );
    }

    my $retval;

    # Update the config "touch file" so that backup metadata can be enabled/disabled as needed.
    # Changes to enable/disable criteria must happen here and Cpanel::Backup::Metadata::metadata_disabled_check()
    if (
        ( defined( $config->{'BACKUPMOUNT'} ) and $config->{'BACKUPMOUNT'} eq 'yes' ) ||             # where did we get abnormal booleans..
        ( defined( $config->{'KEEPLOCAL'} )   and $config->{'KEEPLOCAL'} == 0 )
        || ( defined( $config->{'DISABLE_METADATA'} ) and $config->{'DISABLE_METADATA'} eq 'yes' )
        || ( defined( $config->{'BACKUPACCTS'} )      and $config->{'BACKUPACCTS'} eq 'no' )         # Need to have accounts backed up for metadata
        || ( defined( $config->{'BACKUPENABLE'} )     and $config->{'BACKUPENABLE'} eq 'no' )        # Need to have backups enabled in the first place
    ) {
        Cpanel::SafeDir::MK::safemkdir( $Cpanel::ConfigFiles::backup_config_touchfile_dir, '0755' );
        if ( open( my $touchfile_fh, '>>', $Cpanel::ConfigFiles::backup_config_touchfile ) ) {
            close($touchfile_fh);
        }
    }
    else {
        unlink $Cpanel::ConfigFiles::backup_config_touchfile;
    }

    my $msg;

    # perform validation
    if ( Cpanel::CachedDataStore::store_ref( _get_config_path(), $config ) ) {
        clear_backup_dirs_cache();
        ( $retval, $msg ) = ( 1, 'OK' );
    }
    else {
        ( $retval, $msg ) = ( 0, 'Unable to save config file.' );
    }

    Cpanel::SafeFile::safeunlock($lock);

    return ( $retval, $msg );
}

sub verify_backupdir {
    my ( $backup_dir, $name ) = @_;
    if ( !defined $name ) {
        $name = 'BACKUPDIR';
    }

    # make sure directory paths have a trailing slash so we can easily use regexes to validate paths
    if ( $backup_dir !~ m/\/$/ ) {
        $backup_dir .= '/';
    }

    # use regex patterns for the grep for fine tuning
    my @bad_paths = (
        '^/$',         # root fs mount
        '^/etc/',      # anywhere in /etc
        '^/dev/',      # anywhere in /dev
        '^/sys/',      # anywhere in /sys
        '^/proc/',     # anywhere in /proc
        '^/run/',      # anywhere in /run
        '^/boot/',     # anywhere in /boot
        '^/home/$',    # /home dir itself, allow below it for now
        '^/var/$',     # /var , allow below it (such as /var/backup)
        '^/usr/$',     # /usr , allow below it (such as /usr/backup)
        '\/\.\.\/',    # two periods back to back to prevent directory traversal
        '\\\\',        # any back slashes ( lots of escaping going on here )
        '\0'
    );

    foreach my $regex (@bad_paths) {
        if ( grep /$regex/, $backup_dir ) {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
            $locale ||= Cpanel::Locale->get_handle();
            Cpanel::Debug::log_debug("ERROR: $name rejected because bad matched $regex from \@bad_paths");
            return ( 0, $locale->maketext( 'Invalid value for “[output,class,_1,code]”.', $name ) );
        }
    }

    return ( 1, 'OK' );
}

sub validator {
    my ( $key, $value ) = @_;

    # avoid any mistakes when calling validator
    $key = uc($key) if defined $key;

    # The override should only be used by unit tests
    my $type      = $config_spec->{$key}->{'type'};
    my $types_map = {
        'int' => sub {
            my ($value) = @_;
            return 1 if $value =~ m/^[0-9]+$/;
            return 0;
        },
        'abnormal' => sub {
            my ($value) = @_;
            return 1 if $value eq 'yes' || $value eq 'no';
            return 0;
        },
        'string' => sub {
            my ($value) = @_;
            my $valid = $config_spec->{$key}->{'valid'};
            if ( ref $valid eq 'ARRAY' ) {
                foreach my $allowed ( @{$valid} ) {
                    return 1 if $value eq $allowed;
                }
                return 0;
            }
            else {
                return 0 if ref $value;
                return 0 if $value =~ /\n/sm;

                # We assume that if no valid is provided any one line string is acceptable
                return 1 if $value =~ m/^[A-Za-z0-9 _\-\/=]*^/;
                return 0;
            }
        },
        'bool' => sub {
            my ($value) = @_;
            return 1 if ( $value eq 0 || $value eq 1 );
            return 0;
        },
    };
    if ( exists $config_spec->{$key}->{'valid'}
        && ref $config_spec->{$key}->{'valid'} eq 'CODE' ) {
        return $config_spec->{$key}->{'valid'}->($value);
    }
    elsif ( exists $types_map->{$type} ) {
        return $types_map->{$type}->($value);
    }

    return;
}

sub get_valid_value_for {
    my ( $key, $config ) = @_;

    # load the configuration if not provided
    $config ||= get_normalized_config();

    # check if the current value is valid
    return validator( $key => $config->{ lc($key) } ) ? $config->{ lc($key) } : $config_spec->{ uc($key) }->{'default'};
}

# Used in the unit test
sub _set_config_spec {
    ($config_spec) = @_;
    return;
}

sub _get_config_spec {
    return $config_spec;
}

sub _get_config_path {
    return $config_path;
}

sub hardlinks_supported {
    my ($dir) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Locale') if !$INC{'Cpanel/Locale.pm'};
    $locale ||= Cpanel::Locale->get_handle();

    if ( !-d $dir ) {
        return ( 0, $locale->maketext( 'Directory path “[_1]” is not a directory.', $dir ) );
    }
    my $dest_file = "$dir/.link.test.dest-" . time . "-$$.file";
    if ( -e $dest_file ) {
        return ( 0, $locale->maketext( 'Link destination file “[_1]” exists, this really should not happen.', $dest_file ) );
    }

    #hardlinks have to be on same file system, so origin must be right next to destination
    my $original_file = "$dir/.link.test.src-" . time . "-$$.file";
    if ( -e $original_file ) {
        return ( 0, $locale->maketext( 'Link origin file “[_1]” exists, this really should not happen.', $original_file ) );
    }

    # create our original file with known data
    my $orig_data = "Original file contents here.\n$$\n" . time . "\n";
    if ( open( my $orig_file_fh, '>', $original_file ) ) {
        print {$orig_file_fh} $orig_data;
        close($orig_file_fh);
    }
    else {
        return ( 0, $locale->maketext( 'Could not create origin file “[_1]” for testing hard links: [_2]', $original_file, $! ) );
    }
    if ( !link( $original_file, $dest_file ) ) {
        return ( 0, $locale->maketext( 'Could not create hard link: [_1]', $! ) );
    }
    if ( open( my $dest_fh, '<', $dest_file ) ) {
        my $newdata;
        while (<$dest_fh>) {
            $newdata .= $_;
        }
        close($dest_fh);
        if ( $newdata ne $orig_data ) {
            return ( 0, $locale->maketext( 'Data from destination link did not match original: [_1]', $! ) );
        }
    }
    else {
        return ( 0, $locale->maketext( 'Could not open destination file for reading: [_1]', $! ) );
    }
    if ( !unlink($dest_file) ) {
        return ( 0, $locale->maketext( 'Could not delete our hard link: [_1]', $! ) );
    }
    if ( !unlink($original_file) ) {
        return ( 0, $locale->maketext( 'Could not delete our original file: [_1]', $! ) );
    }
    return 1;
}

# If 'BACKUP' = 0|1 is sent as part of $args, it will force the config, rather than toggling based on current user value.
sub toggle_user_backup_state {
    my ( $args, $metadata ) = @_;

    my $status;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpUserGuard');
    my $guard        = Cpanel::Config::CpUserGuard->new( $args->{'user'} );
    my $userdata_ref = $guard->{'data'};

    # Toggle legacy setting
    if ( $args->{'legacy'} == 1 ) {

        # If BACKUP was overridden via $args, skip the toggle logic
        if ( defined( $args->{'BACKUP'} ) ) {
            if ( $args->{'BACKUP'} == 1 ) {
                $userdata_ref->{'LEGACY_BACKUP'} = 1;
                $status = 1;
            }
            else {
                $userdata_ref->{'LEGACY_BACKUP'} = 0;
                $status = 0;
            }
        }
        else {
            # if it's diabled, enable it, otherwise (if enabled or has some totally wrong value) if it will be disabled
            if ( defined( $userdata_ref->{'LEGACY_BACKUP'} ) && $userdata_ref->{'LEGACY_BACKUP'} == 0 ) {
                $userdata_ref->{'LEGACY_BACKUP'} = 1;
                enablelegacybackupuser( { 'user' => $args->{'user'} } );
                $status = 1;
            }
            else {
                $userdata_ref->{'LEGACY_BACKUP'} = 0;
                disablelegacybackupuser( { 'user' => $args->{'user'} } );
                $status = 0;
            }
        }

        $guard->save();
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'Legacy Backup state modified';

    }
    else {    # Toggle new backup setting

        # If BACKUP was overridden via $args, skip the toggle logic
        if ( defined( $args->{'BACKUP'} ) ) {
            if ( $args->{'BACKUP'} == 1 ) {
                $userdata_ref->{'BACKUP'} = 1;
                $status = 1;
            }
            else {
                $userdata_ref->{'BACKUP'} = 0;
                $status = 0;
            }
        }
        else {
            # if it's disabled, enable it, otherwise (if enabled or has some totally wrong value) it will be disabled
            if ( defined( $userdata_ref->{'BACKUP'} ) && $userdata_ref->{'BACKUP'} == 0 ) {
                $userdata_ref->{'BACKUP'} = 1;
                $status = 1;
            }
            else {
                $userdata_ref->{'BACKUP'} = 0;
                $status = 0;
            }
        }

        $guard->save();
        $metadata->{'result'} = 1;
        $metadata->{'reason'} = 'Backup state modified';
    }
    return ( 1, $status );
}

sub get_backup_users {
    my @user_list;

    my $config = get_normalized_config();

    my $backup_suspended_accts = exists $config->{'backupsuspendaccts'} && $config->{'backupsuspendaccts'} == 1 ? 1 : 0;

    foreach my $user ( Cpanel::Config::Users::getcpusers() ) {
        my $user_conf = Cpanel::Config::LoadCpUserFile::load($user);
        if ( exists $user_conf->{'SUSPENDED'} && $user_conf->{'SUSPENDED'} == 1 && !$backup_suspended_accts ) {
            next;
        }
        if ( defined( $user_conf->{'BACKUP'} ) and $user_conf->{'BACKUP'} == 1 ) {
            push( @user_list, $user );
        }
    }
    return \@user_list;
}

sub getlegacyusers {
    if ( open( my $leg_fh, '<', '/etc/cpbackup-userskip.conf' ) ) {
        my @skipusers;
        while ( my $user = <$leg_fh> ) {
            chomp($user);
            push( @skipusers, $user );
        }
        close($leg_fh);
        return ( 1, \@skipusers );
    }
    else {
        return ( 0, "Could not open /etc/cpbackup-userskip.conf : $!" );
    }
}

sub disablelegacybackupuser {
    my ($opts_ref) = @_;
    if ( !$opts_ref->{'skipfile'} ) { $opts_ref->{'skipfile'} = '/etc/cpbackup-userskip.conf'; }
    if ( !$opts_ref->{'user'} ) {
        return ( 0, 'Required value for user not given' );
    }
    if ( !-f '/var/cpanel/users/' . $opts_ref->{'user'} ) {
        return ( 0, 'No such cPanel user found' );
    }
    my ( $ret, $skipusers_ref ) = getlegacyusers();
    if ( $ret != 1 ) {
        undef $skipusers_ref;
        @{$skipusers_ref} = '';    # we don't need the file to exist here, this could be the first user ever added
    }
    if ( !grep /^$opts_ref->{'user'}$/, @{$skipusers_ref} ) {
        if ( open( my $leg_fh, '>>', $opts_ref->{'skipfile'} ) ) {    # append the user to the file if it's not already there
            print {$leg_fh} $opts_ref->{'user'} . "\n";
            close($leg_fh);
            return ( 1, "User $opts_ref->{'user'} added" );
        }
        else {
            return ( 0, "Could not append to $opts_ref->{'skipfile'} : $!" );
        }
    }
    else {
        return ( 1, "User $opts_ref->{'user'} already exists in $opts_ref->{'skipfile'}" );
    }
}

sub enablelegacybackupuser {
    my ($opts_ref) = @_;
    if ( !$opts_ref->{'skipfile'} ) { $opts_ref->{'skipfile'} = '/etc/cpbackup-userskip.conf'; }
    if ( !$opts_ref->{'user'} ) {
        return ( 0, 'Required value for user not given' );
    }
    if ( !-f '/var/cpanel/users/' . $opts_ref->{'user'} ) {
        return ( 0, 'No such cPanel user found' );
    }
    my ( $ret, $skipusers_ref ) = getlegacyusers();
    if ( $ret != 1 ) {
        undef $skipusers_ref;
        @{$skipusers_ref} = '';    # we don't need the file to exist here, there may not be any users in it at all
    }
    if ( open( my $leg_fh, '>', $opts_ref->{'skipfile'} ) ) {
        foreach my $user ( @{$skipusers_ref} ) {
            chomp($user);
            if ( $user ne $opts_ref->{'user'} ) {    # remove the user by omission ( which turns on backups for it )
                print {$leg_fh} "$user\n";
            }
        }
        close($leg_fh);
        return ( 1, "Removed $opts_ref->{'user'} from $opts_ref->{'skipfile'}" );
    }
    else {
        return ( 0, "Could not write to $opts_ref->{'skipfile'} : $!" );
    }
}

1;
