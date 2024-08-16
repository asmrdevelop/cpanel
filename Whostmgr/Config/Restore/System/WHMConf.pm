package Whostmgr::Config::Restore::System::WHMConf;

# cpanel - Whostmgr/Config/Restore/System/WHMConf.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Whostmgr::Config::Restore::Base );

use Cpanel::Config::Constants       ();
use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::Config::SaveWwwAcctConf ();
use Cpanel::Config::LoadConfig      ();
use Cpanel::Config::LoadCpConf      ();
use Cpanel::FileUtils::Copy         ();
use Cpanel::Hostname                ();
use Cpanel::Themes::Get             ();
use Cpanel::Themes::Utils           ();

sub new {
    my ($class) = @_;

    my $self = $class->SUPER::new();

    $self->{'parent'}   = {};
    $self->{'warnings'} = [];

    return $self;
}

# needed for testing
our $_wwwacctfile  = '/etc/wwwacct.conf';
our $_statsfile    = '/etc/stats.conf';
our $_cpupdatefile = '/etc/cpupdate.conf';
our $_mycnf        = '/etc/my.cnf';            # appended to during restore to my.cnf.$hostname.$epochtime
our $_acllists_dir = '/var/cpanel/acllists';

sub _restore {
    my $self   = shift;
    my $parent = shift;

    $self->parent($parent) if $parent;

    my $backup_path = $parent->{'backup_path'};

    return ( 0, "Backup Path must be an absolute path" ) if ( $backup_path !~ /^\// );

    $self->_restore_wwwacct();
    $self->_restore_stats();
    $self->_restore_mycnf();
    $self->_restore_cpupdate();
    $self->_restore_cpanel_config();
    $self->_restore_acllists();

    return ( 1, __PACKAGE__ . ": ok", { 'warnings' => $self->warnings() } );

}

# Save this for debugging, but deactivate it
sub msglog {

    #my $ts = scalar( localtime(time) );
    #open( my $lfh, '>>', '/tmp/msg.log' ) or die "Cannot open /tmp/msg.log";
    #print $lfh "[$ts] @_\n";
    #close($lfh);
    return;
}

sub post_restore {
    my $self = shift;

    return ( 1, "Update TweakSettings Succeeded" );
}

sub _restore_wwwacct {
    my $self = shift;

    ################################################################################################################
    # /etc/wwwacct.conf
    ################################################################################################################

    my $backup_path = $self->parent->{'backup_path'};

    # Load wwwacct.conf from backup
    $Cpanel::Config::LoadWwwAcctConf::wwwacctconf       = "$backup_path/cpanel/system/whmconf/config/wwwacct.conf";
    $Cpanel::Config::LoadWwwAcctConf::wwwacctconfshadow = "$backup_path/cpanel/system/whmconf/config/wwwacct.conf.shadow";
    my %wwwacct_conf = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    # Delete the server-specific stuff we don't want to restore
    delete @wwwacct_conf{qw/HOST ETHDEV NS NS2 NS3 NS4 ADDR ADDR6 SLAACADDR DEFWEBMAILTHEME/};

    $wwwacct_conf{'DEFMOD'} = _validate_theme( $wwwacct_conf{'DEFMOD'} );

    # Save it to the actual system file by savewwwacctconf's natural merging of new values while leaving original values not in %wwwacct_conf intact
    $Cpanel::Config::LoadWwwAcctConf::wwwacctconf       = $_wwwacctfile;
    $Cpanel::Config::LoadWwwAcctConf::wwwacctconfshadow = $_wwwacctfile . ".shadow";

    if ( !Cpanel::Config::SaveWwwAcctConf::savewwwacctconf( \%wwwacct_conf ) ) {
        push @{ $self->warnings() }, "Could not save wwwacct.conf : $! ";
    }

    return 1;
}

sub _validate_theme {
    my ($theme) = @_;

    if ( $theme && Cpanel::Themes::Utils::theme_is_valid($theme) && !$Cpanel::Themes::Get::EOL_THEMES{$theme} ) {
        return $theme;
    }

    return $Cpanel::Config::Constants::DEFAULT_CPANEL_THEME;
}

sub _restore_stats {
    my $self = shift;

    my $backup_path = $self->parent->{'backup_path'};

    ################################################################################################################
    # /etc/stats.conf
    ################################################################################################################
    my $statsconf_path         = "$backup_path/cpanel/system/whmconf/config/stats.conf";
    my $existingstatsconf_path = $_statsfile;

    my %stats_protected = ( 'VALIDUSERS' => undef );

    if ( !-r "$statsconf_path" ) {
        push @{ $self->warnings() }, "stats.conf is missing from the backup or could not be read.";
    }
    else {
        my ( $stats_conf_hr, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig($statsconf_path);
        if ( !$stats_conf_hr ) {
            push @{ $self->warnings() }, "Failed to load $statsconf_path: $! ($err)";
        }
        else {
            my ( $exim_hr, undef, undef, $err ) = Cpanel::Config::LoadConfig::loadConfig($existingstatsconf_path);
            warn "Failed to load “$existingstatsconf_path”: $err" if !$exim_hr;

            foreach my $key ( keys %stats_protected ) {
                if ( exists( $stats_conf_hr->{$key} ) ) {
                    delete $stats_conf_hr->{$key};
                    push( @{ $self->warnings() }, "Not updating protected value for: $key" );
                }
            }

            my %final_config;
            if ($exim_hr) {
                %final_config = ( %$exim_hr, %$stats_conf_hr );
            }
            else {
                %final_config = %$stats_conf_hr;
            }
            rename( $_statsfile, $_statsfile . '-' . time ) if -e $_statsfile;
            if ( open( my $stats_fh, '>', $_statsfile ) ) {
                foreach my $stats_key ( keys %final_config ) {
                    print $stats_fh "$stats_key=" . $final_config{$stats_key} . "\n";
                }
                close($stats_fh);
            }
            else {
                push( @{ $self->warnings() }, "Could not open /etc/stats.conf for writing : $!" );
            }
        }
    }

    return 1;
}

sub _restore_mycnf {
    my $self = shift;

    my $backup_path = $self->parent->{'backup_path'};

    ################################################################################################################
    # /etc/my.cnf
    ################################################################################################################
    my $hostname = Cpanel::Hostname::gethostname() || 'UnknownHostName';
    my $time     = time;

    my $mycnf = "$backup_path/cpanel/system/whmconf/config/my.cnf";
    if ( !-r "$mycnf" ) {
        push( @{ $self->warnings() }, "my.cnf is missing from the backup or could not be read." );
    }
    else {
        $_mycnf .= ".$hostname.$time";
        Cpanel::FileUtils::Copy::safecopy( $mycnf, $_mycnf );
    }

    return 1;
}

sub _restore_cpupdate {
    my $self = shift;

    my $backup_path = $self->parent->{'backup_path'};

    ################################################################################################################
    # /etc/cpupdate.conf
    ################################################################################################################
    my $cpupdateconf = "$backup_path/cpanel/system/whmconf/config/cpupdate.conf";
    if ( !-r "$cpupdateconf" ) {
        push( @{ $self->warnings() }, "cpupdate.conf is missing from the backup or could not be read." );
    }
    else {
        rename( $_cpupdatefile, $_cpupdatefile . '-' . time );
        Cpanel::FileUtils::Copy::safecopy( $cpupdateconf, $_cpupdatefile );
    }

    return 1;
}

sub _restore_cpanel_config {
    my $self = shift;

    my $backup_path = $self->parent->{'backup_path'};

    ################################################################################################################
    # /var/cpanel/cpanel.config
    ################################################################################################################

    require Whostmgr::TweakSettings;

    if ( !-r "$backup_path/cpanel/system/whmconf/config/cpanel.config" ) {
        push( @{ $self->warnings() }, "cpanel.config is missing from the backup or could not be read." );
    }
    else {
        my $orig_cpconf_hr   = Cpanel::Config::LoadCpConf::loadcpconf();
        my $settings_to_keep = $self->_get_settings_to_keep();

        my $new_cpconf_hr = Cpanel::Config::LoadConfig::loadConfig(
            "$backup_path/cpanel/system/whmconf/config/cpanel.config", undef,
            undef, undef, undef, 1, { 'nocache' => 1 }
        );

        if ( !keys %$new_cpconf_hr ) {
            return ( 0, "Failed to load cpanel.config even though it existed in the backup" );
        }

        # There are some settings that we do not want to transfer here
        # such as apache_port since it is potentially specific to an IP
        # that would not be on the destination server
        foreach my $setting (@$settings_to_keep) {
            $new_cpconf_hr->{$setting} = $orig_cpconf_hr->{$setting};
        }

        my $services_enabled_status = Cpanel::Config::LoadConfig::loadConfig("$backup_path/cpanel/system/whmconf/config/services.config");

        Whostmgr::TweakSettings::apply_module_settings( 'Main', $new_cpconf_hr, 0, { 'services_enabled_status' => $services_enabled_status } );
    }

    return 1;
}

sub _restore_acllists {
    my $self = shift;

    my $backup_path = $self->parent->{'backup_path'};

    ################################################################################################################
    # /var/cpanel/acllists
    ################################################################################################################

    my $acllists_archive_dir = 'cpanel/system/whmconf/config/acllists';

    # Actual restoration is handled in parent's restore(), which is called in cpconftool.
    if ( -e "$backup_path/$acllists_archive_dir" ) {
        $self->parent->{'dirs_to_copy'}->{$_acllists_dir} = { 'archive_dir' => $acllists_archive_dir };
    }

    return 1;
}

sub _get_settings_to_keep {
    my ($self) = @_;

    my @settings_to_keep = qw[
      apache_port
      apache_ssl_port
    ];
    return \@settings_to_keep;
}

sub parent {
    my ( $self, $parent ) = @_;

    $self->{'parent'} = $parent if defined $parent;

    return $self->{'parent'};
}

sub warnings {
    my $self = shift;
    return $self->{'warnings'};
}

1;
