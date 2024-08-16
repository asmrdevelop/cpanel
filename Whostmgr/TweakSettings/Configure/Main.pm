package Whostmgr::TweakSettings::Configure::Main;

# cpanel - Whostmgr/TweakSettings/Configure/Main.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent 'Whostmgr::TweakSettings::Configure::Base';
use Cpanel::Config::CpConfGuard ();
use Cpanel::Debug               ();
use Try::Tiny;

# These must be changed in the background
my %services_conf_names = (
    'mailserver'            => 1,
    'ftpserver'             => 1,
    'local_nameserver_type' => 1
);
my %services_setup_service_names = (
    'mailserver'            => 'mailserver',
    'ftpserver'             => 'ftpserver',
    'local_nameserver_type' => 'nameserver'
);
my %services_enabled_names = (
    'mailserver'            => 'mail',
    'ftpserver'             => 'ftp',
    'local_nameserver_type' => 'dns'
);

# These cannot be modified via restore
my %protected = (
    'roundcube_db' => 'Roundcube',

    # mysql-host ? if they use a remote sql server for 'all the things', this might be good to restore
);

=encoding utf-8

=head1 NAME

Whostmgr::TweakSettings::Configure::Main - Module for applying 'Main' tweak settings.

=head1 SYNOPSIS

    Whostmgr::TweakSettings::apply_module_settings('Main', {'key'=>'value'});

=head1 DESCRIPTION

This module is not intended to be called directly and should only
be called via Whostmgr::TweakSettings.

=head2 new

Creates a new Whostmgr::TweakSettings::Configure::Main object
Only intended to be called from Whostmgr::TweakSettings

=cut

sub new {
    my ( $class, %opts ) = @_;

    my $services_enabled_status = $opts{'services_enabled_status'} || {};
    my $guard                   = Cpanel::Config::CpConfGuard->new( 'no_validate' => 1 );

    return bless {
        '_guard'                          => $guard,
        '_original_data'                  => $guard->config_copy(),
        '_desired_services_enabled_state' => $services_enabled_status,
    }, $class;
}

=head2 pre_process($new_config_hr)

This is a 'fixup' function for the user input.  Currently we only
modify these values for legacy reasons.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub pre_process {
    my ( $self, $new_config_hr ) = @_;

    #XXX FIXME UGLY HACK -- ZOMG THIS IS AWFUL!!!!
    #Duplication of logic in Cpanel/Config/CpConfGuard/Validate.pm
    if ( $new_config_hr->{'overwritecustomproxysubdomains'} ) {
        $new_config_hr->{'proxysubdomainsoverride'} = 0;
    }

    # remove cpanalyticsd from missing dormant services list - LC-8087 needs to remove this workaround
    if ( !-e '/var/cpanel/feature_toggles/analytics_service_manager' ) {
        delete $new_config_hr->{'dormant_services'} if $new_config_hr->{'dormant_services'} && $new_config_hr->{'dormant_services'} eq 'cpanalyticsd';
    }

    return;

}

=head2 get_conf()

Returns the current configuration key value pairs for the module.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub get_conf {
    return $_[0]->{'_guard'}->{'data'};
}

=head2 set($key, $value)

Set a tweak setting key and value.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub set {
    my ( $self, $key, $value ) = @_;

    my $serialized;

    # Fix up multi-valued options.
    if ( ref $value eq 'HASH' ) {
        $serialized = join( ',', grep { $value->{$_} } keys %$value );
    }
    else {
        $serialized = $value;
    }

    if ( $protected{$key} && $self->{'_guard'}{'data'} ne $serialized ) {
        Cpanel::Debug::log_warn("The system cannot restore the “$key” setting, it must be modified by the “$protected{$key}” subsystem.");
        return 0;
    }
    elsif ( $key eq 'mysql-version' ) {
        $self->{'_want_mysql-version'} = $serialized;
        return 0;
    }

    return $self->{'_guard'}->set( $key, $serialized );
}

=head2 save

Commits modification of tweaksettings key values pairs.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub save {
    return $_[0]->{'_guard'}->save();
}

=head2 save

Aborts modification of tweaksettings key values pairs.
Only intended to be called from Whostmgr::TweakSettings

=cut

sub abort {
    return $_[0]->{'_guard'}->abort();
}

=head2 save

After tweaksettings key value pairs have been saved and post_actions have
been run finish is called.  This takes care of restarting any services
or doing any updates that need to be done after groups of settings
are changed for the 'Main' module.

Only intended to be called from Whostmgr::TweakSettings

=cut

sub finish {
    my ($self) = @_;

    $self->_process_service_changes();

    $self->_process_mysql_service_upgrades();

    my $old_config_hr = $self->get_original_conf();
    my $new_config_hr = $self->get_conf();

    my $changed_email_send_limits =
      scalar grep { index( $_, 'email_send_limits' ) == 0 && ( $old_config_hr->{$_} // '' ) ne ( $new_config_hr->{$_} // '' ) } keys %$new_config_hr;

    if ($changed_email_send_limits) {
        require Cpanel::Userdomains;
        Cpanel::Userdomains::updateuserdomains();    #update /etc/email_send_limits
    }

    require Cpanel::Signal;
    Cpanel::Signal::send_hup_cpsrvd();
    Cpanel::Signal::send_hup_dnsadmin();

    # Must be done after releasing the cpanel.config lock.
    Cpanel::Signal::send_hup_cpanellogd();

    return;
}

sub _process_mysql_service_upgrades {
    my ($self) = @_;

    my $old_config_hr = $self->get_original_conf();
    my $new_config_hr = $self->get_conf();

    if ( $self->{'_want_mysql-version'} ) {
        if ( $old_config_hr->{'mysql-version'} ne $self->{'_want_mysql-version'} ) {
            require Whostmgr::Mysql::Upgrade;
            my $upgrade_id;
            try {
                $upgrade_id = Whostmgr::Mysql::Upgrade::unattended_background_upgrade(
                    {
                        upgrade_type     => 'unattended_manual',
                        selected_version => $self->{'_want_mysql-version'}
                    }
                );

            }
            catch {
                Cpanel::Debug::log_warn($_);
            };

            if ($upgrade_id) {
                Cpanel::Debug::log_info("MySQL upgrade started in background with upgrade_id: $upgrade_id");
            }
        }
    }

    return;
}

sub _process_service_changes {
    my ($self) = @_;

    my $old_config_hr = $self->get_original_conf();
    my $new_config_hr = $self->get_conf();

    require Cpanel::Services::Enabled;

    foreach my $service ( keys %services_setup_service_names ) {
        my $selected_server_value = $new_config_hr->{$service} or next;    # may be bind, nsd, etc

        my $setup_service_name = $services_setup_service_names{$service};
        my $enabled_key        = $services_enabled_names{$service};

        my $current_enabled_state = Cpanel::Services::Enabled::is_enabled($enabled_key);
        my $desired_enabled_state = ( $self->{'_desired_services_enabled_state'}{$setup_service_name} //= $current_enabled_state );

        if (   $old_config_hr->{$service} eq $new_config_hr->{$service}
            && $current_enabled_state == $desired_enabled_state ) {
            next;
        }
        my $task = "setupservice $setup_service_name $selected_server_value";
        if ( !$desired_enabled_state ) {
            $task .= " disabled";
        }

        require Cpanel::ServerTasks;
        Cpanel::ServerTasks::schedule_task( ['CpServicesTasks'], 1, $task );
    }
    return 1;
}

1;
