package Cpanel::Backup::Utility;

# cpanel - Cpanel/Backup/Utility.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Try::Tiny;

use Cpanel::Backup::Config          ();
use Cpanel::Backup::Transport       ();
use Cpanel::Config::Backup          ();
use Cpanel::Config::CpUserGuard     ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::Config::Users           ();
use Cpanel::CpuWatch                ();
use Cpanel::Exception               ();
use Cpanel::ExitValues::rsync       ();    # PPI USE OK -- use dynamically Cpanel::ExitValues::$x
use Cpanel::ExitValues::tar         ();    # PPI USE OK -- use dynamically Cpanel::ExitValues::$x
use Cpanel::Binaries                ();
use Cpanel::Gzip::Config            ();
use Cpanel::Kill::Single            ();
use Cpanel::Logger                  ();
use Cpanel::SafeRun::Errors         ();
use Cpanel::Backup::Utility::Legacy ();
use Cpanel::SignalManager           ();
use Cpanel::Tar                     ();
use Cpanel::Transport::Files        ();

use Whostmgr::Templates::Chrome::Rebuild ();

# This file is used for breaking out pre-execution decisions made by
# bin/backup

# This subroutine is responsible for determining the various
# parameters that different dependent applications
# should be run with.
#
# This will return a datastructure following the below format:
#
#{
#   'gzip' => {
#       'bin' => '/some/path',
#       'cfg' => Cpanel::Gzip::Config::load(),
#   },
#   'rsync' => {
#       'bin' => '/some/path',
#       'cfg' => ..
#   }
#   .. and so on for various different dependent applications
#}

sub new {
    my ( $class, $conf_ref ) = @_;

    my $self = bless {
        'conf' => $conf_ref,
    }, $class;

    for my $app (qw( gzip  rsync  tar  pkgacct )) {
        $self->_set_app( $app, $self->can("_determine_$app")->($self) );
    }

    $self->{'cpconf'} = Cpanel::Config::LoadCpConf::loadcpconf();

    return $self;
}

#Used in tests
sub _set_app {
    my ( $self, $name => $data ) = @_;
    return $self->{'apps'}{$name} = $data;
}

sub set_logger {
    my ( $self, $logger_obj ) = @_;

    return $self->{'_logger'} = $logger_obj;
}

sub _logger {
    my ($self) = @_;

    return $self->{'_logger'} ||= Cpanel::Logger->new();
}

# Set the gzip environment variables
sub set_env_variables {
    my ($self) = @_;
    if ( ( $self->{'conf'}->{'GZIPRSYNCOPTS'} || '' ) !~ /--rsyncable/ ) {
        my $gzip_cfg = Cpanel::Gzip::Config->load();
        my $gzip_bin = $gzip_cfg->{'bin'} // '';

        if ( !-x $gzip_bin ) {
            $self->_logger()->warn("Error: Compression utility not available: $gzip_bin");
        }
        elsif ( $gzip_cfg->{'rsyncable'} ) {
            _concat( \$self->{'conf'}->{'GZIPRSYNCOPTS'}, "--rsyncable" );
            my ( $ret, $msg ) = Cpanel::Backup::Config::save( $self->{'conf'} );
            if ( $ret != 1 ) {
                $self->_logger()->warn("Error encountered trying to save backup configuration: $msg");
            }
        }
    }
    my %CONF = Cpanel::Config::Backup::load();
    _concat( \$ENV{'GZIP'}, $self->{'conf'}->{'GZIPRSYNCOPTS'} );

    # Ensure these are set properly
    if ( $> == 0 ) {
        $ENV{'USER'} = 'root';
        $ENV{'HOME'} = '/root';
    }

    $ENV{'CPBACKUP'} = 1;

    if ( !$self->{'cpconf'}{'skipnotifyacctbackupfailure'} ) {
        $ENV{'CPBACKUP_NOTIFY_FAIL'} = 1;
    }
    return;
}

sub set_signal_manager {
    my ( $self, $sigman ) = @_;

    die "wrong type: $sigman" if !try { $sigman->isa('Cpanel::SignalManager') };

    return $self->{'_signal_manager'} = $sigman;
}

# Convenience method for grabbing the values defined by _determine_*
sub get_app_value {
    my ( $self, $app, $key ) = @_;
    if ( !exists $self->{'apps'}->{$app} ) {
        $self->_logger()->warn("No such application: $app");
        return;
    }

    return $self->{'apps'}->{$app}->{$key};
}

# Convenience function for getting the binary for an application
sub get_binary {
    my ( $self, $app ) = @_;
    return $self->get_app_value( $app, 'bin' );
}

# Convenience function got getting the config for an application
sub get_config {
    my ( $self, $app ) = @_;
    return $self->get_app_value( $app, 'cfg' );
}

# Run an external program. For historical purposes, this warn()s
# rather than die()ing, and returns 0 on success and 1 on failure.
#
sub cpusystem {
    my ( $self, $app, @args ) = @_;
    my $bin = $self->get_binary($app);

    my $sigman;

    $self->{'_cpusystem_error'} = undef;

    my @FATAL_SIGNALS = Cpanel::SignalManager->FATAL_SIGNALS();

    my $ok;
    try {
        local $ENV{'CPBACKUP'} = 1;
        local $SIG{'__WARN__'} = sub { };
        local $SIG{'__DIE__'}  = 'DEFAULT';
        local $SIG{$_}         = 'DEFAULT' for @FATAL_SIGNALS;
        Cpanel::CpuWatch::run(

            # Avoid before_exec as it will prevent
            # fastspawn
            keep_env   => 1,
            program    => $bin,
            args       => \@args,
            stdout     => \*STDOUT,
            stderr     => \*STDERR,
            after_fork => sub {
                my ($child_pid) = @_;

                my $infanticide_cr = sub {
                    Cpanel::Kill::Single::safekill_single_pid($child_pid);
                };

                if ( $self->{'_signal_manager'} ) {
                    $sigman = $self->{'_signal_manager'};
                }
                else {
                    $sigman = Cpanel::SignalManager->new();
                    for (@FATAL_SIGNALS) {
                        $sigman->enable_signal_resend( signal => $_ );
                    }
                }

                for my $sig (@FATAL_SIGNALS) {
                    $sigman->push(
                        signal  => $sig,
                        name    => 'infanticide',
                        handler => $infanticide_cr,
                    );
                }
            },
        );

        $ok = 1;
    }
    catch {
        my $exception = $_;
        $self->{'_cpusystem_error'} = $exception;

        #Accommodate acceptable error codes.
        my $exit_vals_mod = $self->get_app_value( $app, 'ExitValues' );
        if ($exit_vals_mod) {
            my $mod = "Cpanel::ExitValues::$exit_vals_mod";

            if ( $mod->can('error_is_nonfatal_for_cpanel') ) {
                if ( try { $exception->isa('Cpanel::Exception::ProcessFailed::Error') } ) {
                    my $errcode = $exception->get('error_code');

                    $ok = $mod->error_is_nonfatal_for_cpanel($errcode);
                    if ($ok) {
                        my $errstr = $mod->number_to_string($errcode);

                        #warn() would print a stack trace, which we don’t want.
                        print STDERR "$bin returned a non-fatal error code, $errcode ($errstr).\n";
                    }
                }
            }
        }

        if ( !$ok ) {
            $self->_logger()->warn( Cpanel::Exception::get_string($exception) );
        }
    }
    finally {
        if ( $self->{'_signal_manager'} && $sigman ) {
            for my $sig ( $sigman->FATAL_SIGNALS() ) {
                $sigman->delete( name => 'infanticide', signal => $sig );
            }
        }
    };

    return $ok ? 0 : 1;    #Historical: 0 for success, 1 for failure.
}

sub cpusystem_error {
    my ($self) = @_;
    return $self->{'_cpusystem_error'};
}

sub _determine_pkgacct {
    my ($self) = @_;
    my $app_hr = {};

    my $pkgacct = -x '/usr/local/cpanel/bin/pkgacct' ? '/usr/local/cpanel/bin/pkgacct' : '/usr/local/cpanel/scripts/pkgacct';
    $app_hr->{'bin'} = $pkgacct;
    return $app_hr;
}

sub allow_pkgacct_override {
    my ($self) = @_;
    if ( _pkgacct_override_exists() ) {
        $self->{'apps'}{'pkgacct'}{'bin'} = '/var/cpanel/lib/Whostmgr/Pkgacct/pkgacct';
    }
    return;
}

sub _pkgacct_override_exists {
    return -e '/var/cpanel/lib/Whostmgr/Pkgacct/pkgacct' && -x _;
}

sub _determine_tar {
    my ($self) = @_;
    my $app_hr = {
        ExitValues => 'tar',
    };

    $app_hr->{'cfg'} = Cpanel::Tar::load_tarcfg();
    $app_hr->{'bin'} = $app_hr->{'cfg'}->{'bin'};
    my ( $status, $message ) = Cpanel::Tar::checkperm();
    if ( !$status ) {
        $self->_logger()->die("Could not locate suitable tar binary.");
    }

    return $app_hr;
}

sub _determine_rsync {
    my ($self) = @_;

    my $app_hr = {
        ExitValues => 'rsync',
    };

    $app_hr->{'bin'} = Cpanel::Binaries::path('rsync');

    if ( !-x $app_hr->{'bin'} ) {
        $self->_logger()->die("Unable to locate suitable rsync binary");
    }

    $app_hr->{'cfg'}           = '-rlptD';
    $app_hr->{'has_link_dest'} = 0;

    if (
           $self->{'conf'}->{'BACKUPTYPE'} eq 'incremental'
        && $self->{'conf'}->{'LINKDEST'}
        && (   $self->{'conf'}->{'LINKDEST'} eq 'yes'
            || $self->{'conf'}->{'LINKDEST'} eq '1' )
    ) {
        my $rsync_help = Cpanel::SafeRun::Errors::saferunallerrors( $app_hr->{'bin'}, '--help' );
        $app_hr->{'has_link_dest'} = ( $rsync_help =~ /link-dest/ ? 1 : 0 );
    }
    else {
        $app_hr->{'has_link_dest'} = 0;
    }
    return $app_hr;

}

sub _determine_gzip {
    my ($self) = @_;
    my $app_hr = {};
    $app_hr->{'cfg'} = Cpanel::Gzip::Config->load();
    $app_hr->{'bin'} = $app_hr->{'cfg'}->{'bin'};

    if ( !-x $app_hr->{'bin'} ) {
        $self->_logger()->die("Unable to locate suitable gzip binary");
    }
    return $app_hr;
}

# handle space delimiter properly, and suppress warnings
sub _concat {
    my ( $first_ref, $second ) = @_;
    $$first_ref = ( $$first_ref || '' ) . ( $$first_ref && $second ? ' ' : '' ) . ( $second || '' );
    return;
}

###############################################################
# Function for converting legacy config to new config & migrate
###############################################################

sub get_legacy_to_new_map {
    my %map = (
        'BACKUPACCTS'      => 'BACKUPACCTS',
        'GZIPRSYNCOPTS'    => 'GZIPRSYNCOPTS',
        'PREBACKUP'        => 'PREBACKUP',
        'POSTBACKUP'       => 'POSTBACKUP',
        'BACKUPDAYS'       => 'BACKUPDAYS',
        'BACKUPBWDATA'     => 'BACKUPBWDATA',
        'BACKUPDIR'        => 'BACKUPDIR',
        'BACKUPMOUNT'      => 'BACKUPMOUNT',
        'USEBINARYPKGACCT' => 'USEBINARYPKGACCT',
        'BACKUPENABLE'     => 'BACKUPENABLE',
        'LINKDEST'         => 'LINKDEST',
        'BACKUPFILES'      => 'BACKUPFILES',
        'BACKUPLOGS'       => 'BACKUPLOGS',
        'LOCALZONESONLY'   => 'LOCALZONESONLY',
        'MYSQLBACKUP'      => 'MYSQLBACKUP'
    );
    return \%map;
}

sub _rename_legacy {
    return if !-e $Cpanel::Backup::Utility::Legacy::legacy_conf;

    my $backup_path = $Cpanel::Backup::Utility::Legacy::legacy_conf . '-' . time;
    rename( $Cpanel::Backup::Utility::Legacy::legacy_conf, $backup_path );

    return $backup_path;
}

#
# Enable backups for all users enabled for legacy backups
# This is important to do on migration since the legacy backups will no longer be performed
# That way users being backed up under the old system will still be backed up
# when the system is migrated to the newer backup system.
#
sub upgrade_legacy_backup_users {

    my @user_list = Cpanel::Config::Users::getcpusers();

    foreach my $user (@user_list) {

        my $guard = Cpanel::Config::CpUserGuard->new($user);
        next unless defined $guard;

        my $userdata_ref = $guard->{'data'};

        # Do nothing for users where legacy backup is not enabled
        next if ( !exists $userdata_ref->{'LEGACY_BACKUP'} or $userdata_ref->{'LEGACY_BACKUP'} != 1 );

        # If normal backups are already enabled, we don't need to do anything
        next if ( exists $userdata_ref->{'BACKUP'} and $userdata_ref->{'BACKUP'} == 1 );

        # If we get here, legacy backups are enabled & regular backups are not
        # So, enable regular backups & save
        $userdata_ref->{'BACKUP'} = 1;
        $guard->save();
    }

    return;
}

# break out some of the decision making
sub _backuptype_decision {
    my ( $leg_cnf, $conf_ref ) = @_;

    # Determine backup type to be used, if none of these match, take defaults
    if ( $leg_cnf->{'BACKUPINC'} eq 'yes' ) {
        $conf_ref->{'BACKUPTYPE'} = 'incremental';
    }
    elsif ( $leg_cnf->{'COMPRESSACCTS'} eq 'yes' ) {
        $conf_ref->{'BACKUPTYPE'} = 'compressed';
    }
    elsif ( $leg_cnf->{'COMPRESSACCTS'} eq 'no' ) {
        $conf_ref->{'BACKUPTYPE'} = 'uncompressed';
    }

    return;
}

sub convert_and_migrate_from_legacy_config {

    my (%opts) = @_;

    if ( !-e $Cpanel::Backup::Utility::Legacy::legacy_conf ) {
        return ( 0, "No $Cpanel::Backup::Utility::Legacy::legacy_conf file, nothing to convert." );
    }

    if ( $opts{'no_convert'} ) {
        my $backup_path = _rename_legacy();
        Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();
        return ( 1, "Legacy Backup configuration was renamed from $Cpanel::Backup::Utility::Legacy::legacy_conf to $backup_path as a backup copy for your records." );
    }

    ###########################################################
    # Get legacy config in a hash
    ###########################################################

    my %leg_cnf = Cpanel::Config::Backup::load();

    ###########################################################
    # Load existing new config for defaults and such
    ###########################################################

    my $conf_ref = Cpanel::Backup::Config::load();

    ###########################################################
    # Walk through old values and assign them their new counterparts
    ###########################################################
    my $map_hr = get_legacy_to_new_map();

    foreach my $key ( keys %{$map_hr} ) {

        # Only convert old value to new if we have an existing key name, even if never configured we'll have all the key names
        # that the new backup system knows how to handle by loading defaults, anything else will be cruft
        if ( defined( $conf_ref->{ $map_hr->{$key} } ) ) {
            if ( defined( $leg_cnf{$key} ) ) {
                $conf_ref->{ $map_hr->{$key} } = $leg_cnf{$key};
            }
            else {
                if ( !defined( $conf_ref->{ $map_hr->{$key} } ) ) {
                    $conf_ref->{ $map_hr->{$key} } = '';
                }
            }
        }
    }

    ###########################################################
    # Handle unique conditions
    ###########################################################

    # This is an 'abnormal' boolean in Legacy, regular boolean in new
    if ( $conf_ref->{'LINKDEST'} eq 'yes' ) {
        $conf_ref->{'LINKDEST'} = 1;
    }
    elsif ( $conf_ref->{'LINKDEST'} eq 'no' ) {
        $conf_ref->{'LINKDEST'} = 0;
    }

    # restoreonly is n/a in new backups, you can always restore
    # whether backups are enabled or not
    if ( $conf_ref->{'BACKUPENABLE'} eq 'restoreonly' ) {
        $conf_ref->{'BACKUPENABLE'} = 'no';
    }

    # Determine backup type to be used, if none of these match, take defaults
    _backuptype_decision( \%leg_cnf, $conf_ref );

    # In legacy config, we either do or do not retain a copy of daily/weekly/monthly backups,
    # rather than a number of retention points. If daily backups are not enabled, daily retention
    # is 0. Same for weekly.

    if ( $leg_cnf{'BACKUPRETDAILY'} == 1 ) {
        $conf_ref->{'BACKUP_DAILY_RETENTION'} = 1;
    }
    if ( $leg_cnf{'BACKUPRETWEEKLY'} == 1 ) {
        $conf_ref->{'BACKUP_WEEKLY_RETENTION'} = 1;
    }
    if ( $leg_cnf{'BACKUPRETMONTHLY'} == 1 ) {
        $conf_ref->{'BACKUP_MONTHLY_RETENTION'} = 1;
    }

    # Expand the logic of the old system to that of the new configs for daily/weekly/monthly backups
    if ( $leg_cnf{'BACKUPINT'} eq 'daily' ) {
        $conf_ref->{'BACKUP_DAILY_ENABLE'}   = 'yes';
        $conf_ref->{'BACKUP_WEEKLY_ENABLE'}  = 'yes';
        $conf_ref->{'BACKUP_MONTHLY_ENABLE'} = 'yes';
    }
    elsif ( $leg_cnf{'BACKUPINT'} eq 'weekly' ) {
        $conf_ref->{'BACKUP_DAILY_ENABLE'}   = 'no';
        $conf_ref->{'BACKUP_WEEKLY_ENABLE'}  = 'yes';
        $conf_ref->{'BACKUP_MONTHLY_ENABLE'} = 'yes';
    }
    elsif ( $leg_cnf{'BACKUPINT'} eq 'monthly' ) {
        $conf_ref->{'BACKUP_DAILY_ENABLE'}   = 'no';
        $conf_ref->{'BACKUP_WEEKLY_ENABLE'}  = 'no';
        $conf_ref->{'BACKUP_MONTHLY_ENABLE'} = 'yes';
    }

    ###########################################################
    # Convert users who are only enabled for legacy backups
    # To use the newer backup system
    ###########################################################
    upgrade_legacy_backup_users();

    ###########################################################
    # Convert BACKUPFTPHOST and related to remote destination
    ###########################################################
    # If legacy BACKUPTYPE eq 'ftp' , attempt to create, save and enable it's config as a remote FTP destination
    # otherwise all the FTP related entries can be ignored
    #
    # Note that most if this is taken straight from Whostmgr/API/1/Backup.pm sub backup_destination_add()

    my $new_ftp_destination_ok = 0;
    if ( $leg_cnf{'BACKUPTYPE'} eq 'ftp' ) {
        my %args;
        my $metadata = {};

        $args{'name'}     = 'Legacy FTP Destination';
        $args{'type'}     = 'FTP';
        $args{'host'}     = $leg_cnf{'BACKUPFTPHOST'};
        $args{'username'} = $leg_cnf{'BACKUPFTPUSER'};
        $args{'password'} = $leg_cnf{'BACKUPFTPPASS'};
        $args{'timeout'}  = $leg_cnf{'BACKUPFTPTIMEOUT'};
        $args{'passive'}  = $leg_cnf{'BACKUPFTPPASSIVE'};
        $args{'path'}     = $leg_cnf{'BACKUPFTPDIR'};

        # Handle abnormal boolean logic disparity
        if ( $args{'passive'} eq 'yes' ) {
            $args{'passive'} = 1;
        }
        elsif ( $args{'passive'} eq 'no' ) {
            $args{'passive'} = 0;
        }

        # Verify the args we are saving for the destination are legit
        if ( !Cpanel::Backup::Transport::validate_common( \%args, $metadata ) ) {
            return ( 0, "Failed to validate transport configuration settings." );
        }

        # Sanitize the parameters as well
        my @sanitize_ignore = qw/id name type disabled sessions upload_system_backup only_used_for_logs/;
        Cpanel::Transport::Files::sanitize_parameters( $args{'type'}, \%args, \@sanitize_ignore );

        my $transport = Cpanel::Backup::Transport->new();

        # Make sure 'id' is empty, it will be generated by the 'add' call
        delete $args{'id'};

        # If 'disabled' was not specified, then set to false
        $args{'disabled'} = 0 unless exists $args{'disabled'};

        # Attempt to add the new transport, on success we get an ID
        my $id = $transport->add(%args);
        if ($id) {
            $new_ftp_destination_ok = 1;

            # Apparently $transport->check_destination does not work correctly
            # with the password but ...
            #
            # If I create a new transport object and do check_destination it
            # works, go figure

            my $test_transport = Cpanel::Backup::Transport->new();
            my ( $result, $msg ) = $test_transport->check_destination( $id, 0 );
            if ( $result != 1 ) {
                return ( 0, "There was a failure trying to convert the existing Legacy Backup Config's FTP settings, no changes have been made: " . $msg );
            }
        }
        else {
            return ( 0, "There was a failure trying to convert the existing Legacy Backup Config's FTP settings, no changes have been made: " . $transport->get_error_msg() );
        }
    }

    ###########################################################
    # If conversion made it this far, save new config file
    # and rename cpbackup.conf to time-stamped backup
    ###########################################################

    if ( ( $leg_cnf{'BACKUPTYPE'} eq 'ftp' && $new_ftp_destination_ok == 1 ) || $leg_cnf{'BACKUPTYPE'} ne 'ftp' ) {
        my ( $ret, $msg ) = Cpanel::Backup::Config::save($conf_ref);
        if ($ret) {
            my $backup_path = _rename_legacy();
            Whostmgr::Templates::Chrome::Rebuild::rebuild_whm_chrome_cache();
            return ( 1, "Conversion from Legacy Backup configuration was successful. We renamed $Cpanel::Backup::Utility::Legacy::legacy_conf to $backup_path as a backup copy for your records." );
        }
        else {
            return ( 0, "Unable to save new backup configuration file: $msg" );
        }
    }

    return ( 0, 'Unknown situation is preventing us from converting the Legacy Configuration properly' );
}

1;
