package Cpanel::Update::Config;

# cpanel - Cpanel/Update/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadConfig ();

our $VERSION            = '2.1';
our $cpanel_update_conf = '/etc/cpupdate.conf';

sub _default_preferences {
    return {
        'CPANEL'      => 'release',
        'RPMUP'       => 'daily',
        'SARULESUP'   => 'daily',
        'UPDATES'     => 'daily',
        'STAGING_DIR' => '/usr/local/cpanel',
    };
}

sub valid_keys {

    # If you update this list be sure to reflect those changes in the 'update_updateconf' hash’s 'args' in whostmgr/bin/xml-api.pl
    # note that BSDPORTS, EXIMUP and SYSUP are now invalid keys
    return [qw/CPANEL RPMUP SARULESUP UPDATES STAGING_DIR/];
}

sub load {
    my $default_rUPCONF = _default_preferences();

    if ( ${^GLOBAL_PHASE} && ${^GLOBAL_PHASE} eq 'START' && lc($0) ne '-e' ) {
        die q[FATAL: load is called during compile time. You should postpone this call.];
    }

    # save and return the defaults if there is no local configuration
    if ( !-e $cpanel_update_conf ) {
        save($default_rUPCONF);
        return wantarray ? %{$default_rUPCONF} : $default_rUPCONF;
    }

    my $rUPCONF = Cpanel::Config::LoadConfig::loadConfig($cpanel_update_conf);
    my $changed = sanitize($rUPCONF);

    # Default any settings not present in the file.
    foreach my $key ( keys %{$default_rUPCONF} ) {
        if ( !exists $rUPCONF->{$key} ) {
            $changed++;
            $rUPCONF->{$key} = $default_rUPCONF->{$key};
        }
    }

    save($rUPCONF) if $changed;

    return wantarray ? %{$rUPCONF} : $rUPCONF;
}

# sanitize the values in the passed hash
# Lowercase all values. Remove any errant newline chars. s/undef/''/;
# returns number of changes made.
sub sanitize {
    my $conf_ref       = shift;
    my $die_on_failure = shift;

    return if ref $conf_ref ne 'HASH';

    my $changed = 0;

    my $valid_keys = valid_keys();

    foreach my $key ( keys %{$conf_ref} ) {

        # remove invalid values
        if ( !grep { $key eq $_ } @$valid_keys ) {
            delete $conf_ref->{$key};
            $changed++;
            next;
        }

        my $value = $conf_ref->{$key};

        # Regardless of key, we want to strip off the cruft and re-save if necessary.
        if ($value) {
            $changed++ if ( $value                   =~ s/[\n\r]//g );    # Strip newline chars
            $changed++ if ( $value                   =~ s/^\s+// );       # Strip leading whitespace
            $changed++ if ( $value                   =~ s/\s+$// );       # Strip trailing whitespace
            $changed++ if ( $value ne '/' and $value =~ s{/+$}{} );       # Strip trailing slash. This is for STAGING_DIR but nothing else should have a slash in its value.

            # Lowercase all values unless the key is for a file path.
            if ( $key ne 'STAGING_DIR' ) {
                $changed++ if ( $value =~ tr/A-Z/a-z/ );
            }
        }

        # Staging_dir paths have special pass/fail values. We just switch to default if we think the value is wrong.
        if ( $key eq 'STAGING_DIR' and not validate_staging_dir( $value, $die_on_failure ) ) {
            $value = _default_preferences()->{'STAGING_DIR'};
            $changed++;                                                   # Flag for file save
        }

        # If the value is undef, set it to '' but not until we've done STAGING_DIR acrobatics.
        if ( !defined $value ) {
            $value = '';
            $changed++;
        }

        $conf_ref->{$key} = $value;
    }

    return $changed;
}

# For testing.
sub _stat_directory {
    my $dir = shift;
    return stat($dir);
}

sub validate_staging_dir {

    my ( $value, $die_on_failure ) = @_;
    my $ulc     = '/usr/local/cpanel';
    my $ulc_dev = ( _stat_directory($ulc) )[0];

    # If the value is blank, then we silently fail instead of dieing
    # as this is a case where we want to always fallback to using ULC.
    return if not $value;

    # The rest of the checks, die on failure, if the second arg is true. Otherwise, they return undef on failure.
    # Fail if specified path is not a valid file path.
    if ( !_is_valid_filepath($value) ) {
        die "'$value' is not a valid directory path\n" if $die_on_failure;
        return;
    }

    # If it's a valid filepath, but we can't stat it
    # then it doesn't exist on the system. So we skip the remaining tests.
    my @stat = _stat_directory($value) or return 1;

    # Fail if specified path exists on the system, but is not a directory.
    if ( -e $value && !-d $value ) {
        die "'$value' exists on the file system, but is not a directory\n" if $die_on_failure;
        return;
    }

    # Fail if specified path is a directory that exists, but not something we can write to.
    if ( -e $value && ( !-d $value || !( -d $value && -w $value ) ) ) {
        die "'$value' exists on the file system, but is not a writable directory\n" if $die_on_failure;
        return;
    }

    # Fail if specified path is a directory but is not owned by 'root'
    if ( 0 != $stat[4] ) {
        die "'$value' exists on the file system, but is not owned by the root user\n" if $die_on_failure;
        return;
    }

    if ( $stat[0] == $ulc_dev && $value ne $ulc ) {
        die "'$value' is on the same file system as /usr/local/cpanel. Please use /usr/local/cpanel instead.\n" if $die_on_failure;
        return;
    }

    # Fail if specified path's permissions allow group or world write access.
    if ( $stat[2] & 022 ) {
        die "'$value' exists on the file system, but does not have the correct permissions. Directory must not have write permissions for group and non-root users\n" if $die_on_failure;
        return;
    }

    return 1;
}

sub save {
    my $conf_ref       = shift;
    my $die_on_failure = shift;

    return if ref $conf_ref ne 'HASH';

    # do not try to save the config if the code is not running as root
    # since $cpanel_update_conf is owned by root and an unprivileged user
    # will not have sufficient perms to write to the file
    # NOTE: I am choosing not to emit a warning here since one of the callers to
    # save() is load() and an unprivileged user should be able to call load() without
    # warnings
    return if ( $> != 0 );

    sanitize( $conf_ref, $die_on_failure );

    # Write config file
    require Cpanel::Config::FlushConfig;
    if ( my $return = Cpanel::Config::FlushConfig::flushConfig( $cpanel_update_conf, $conf_ref, '=', undef, { 'sort' => 1 } ) ) {
        return $return;
    }
    else {
        die "Unable to save file, $cpanel_update_conf: $!\n" if $die_on_failure;
        return;
    }
}

# Reads tier setting from updateconfig
sub get_tier {
    my ($update_config_ref) = @_;

    if ( !defined $update_config_ref ) {
        $update_config_ref = load();
    }

    return if ( ref $update_config_ref ne 'HASH' );

    return $update_config_ref->{'CPANEL'};
}

# Centralized logic to understand if a given option is currently enabled.
# used in maintenance, updatenow, install_cppkg scripts to see if an update is allowed or not.
sub is_permitted {
    my $key     = shift or return;
    my $up_conf = shift or return;
    ref $up_conf eq 'HASH' or return;

    $key = uc($key);    # Force key case upper.
    my $key_value = $up_conf->{$key} or return;

    return if ( $key eq 'RPMUP' && $ENV{'CPANEL_BASE_INSTALL'} );
    return if ( $key_value eq 'never' );
    return if ( $ENV{'CPANEL_IS_CRON'} && $key_value eq 'manual' );
    return 1;
}

sub get_update_type {
    my $rUPCONF = load();
    return $rUPCONF->{'UPDATES'};
}

sub _is_valid_filepath {
    my $filepath = shift;
    return 1 if index( $filepath, '/' ) == 0;    # checking for / is the same as file_name_is_absolute
    return;
}

1;
