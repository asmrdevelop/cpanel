package Cpanel::Chkservd::Manage;

# cpanel - Cpanel/Chkservd/Manage.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Chkservd::Tiny            ();
use Cpanel::Chkservd::Config::Drivers ();
use Cpanel::Chkservd::Config          ();
use Cpanel::Server::Type              ();
use Cpanel::LoadModule                ();

our $VERSION = '0.7';
our %DRIVERS;

our $src_chkservd_dir = '/usr/local/cpanel/src/chkservd/chkserv.d';
our $alt_chkservd_dir = '/var/cpanel/chkservd/drivers';

# Loads all available drivers
sub load_drivers {

    # %DRIVERS was already loaded
    if ( scalar keys %DRIVERS ) {
        return wantarray ? %DRIVERS : \%DRIVERS;
    }

    _update_driver_files();
    Cpanel::Chkservd::Config::Drivers::load_driver_directory( $Cpanel::Chkservd::Config::chkservd_dir, \%DRIVERS );

    # Remove services that no longer exist and don't require any monitoring
    my $skipped_services = _get_skipped_services();
    foreach my $skipped_service ( keys %{$skipped_services} ) {
        delete $DRIVERS{$skipped_service};
    }

    return wantarray ? %DRIVERS : \%DRIVERS;
}

sub getmonitored {
    my %MONITORED;

    my $skipped_services = _get_skipped_services();
    if ( open my $chkservdconf_fh, '<', $Cpanel::Chkservd::Tiny::chkservd_conf ) {
        while ( my $line = readline $chkservdconf_fh ) {
            chomp $line;
            my ( $service, $status ) = split( /\s*:\s*/, $line );
            next if !$service || ( !defined $status || $status eq '' ) || $skipped_services->{$service};
            $MONITORED{$service} = int $status;
        }
        close $chkservdconf_fh;
    }

    my $always_monitored = get_always_monitored();

    foreach my $service ( keys %{$always_monitored} ) {
        $MONITORED{$service} = 1;
    }

    return wantarray ? %MONITORED : \%MONITORED;
}

sub disable {
    my ($service) = @_;

    # Sanity check
    if ( !$service || $service =~ m{\s} ) {
        _logger()->warn('No service specified.');
        return;
    }

    # Check to see if you can't disable it
    my $always_monitored = get_always_monitored();
    return 0 if grep { $_ eq $service } keys(%$always_monitored);

    # Check to see if it is already disabled
    my $chksrvd_conf_hr = getmonitored();
    return 1 if defined $chksrvd_conf_hr->{$service} && $chksrvd_conf_hr->{$service} == 0;

    $chksrvd_conf_hr->{$service} = 0;
    return save_chkservd_conf_hashref($chksrvd_conf_hr);
}

sub enable {
    my ($service) = @_;

    # Sanity check
    if ( !$service || $service =~ m{\s} ) {
        _logger()->warn('No service specified');
        return;
    }

    if ( $service eq 'cpdavd' ) {
        require Cpanel::ServiceConfig::cpdavd;
        Cpanel::ServiceConfig::cpdavd::die_if_unneeded();
    }

    my $skipped_services = _get_skipped_services();
    if ( $skipped_services->{$service} ) {
        _logger()->info("Skipping chkservd $service monitoring. It is no longer needed.");
        return;
    }

    load_drivers();
    if ( !$DRIVERS{$service} ) {
        _logger()->warn("Invalid service. Unable to locate chkservd $service driver.");
        return;
    }

    # Check to see if it is already monitored
    my $chksrvd_conf_hr = getmonitored();
    return 1 if $chksrvd_conf_hr->{$service};

    # Sanity check to remove any stray skipped services
    foreach my $skipped_service ( keys %{$skipped_services} ) {
        delete $chksrvd_conf_hr->{$skipped_service};
    }

    $chksrvd_conf_hr->{$service} = 1;
    return save_chkservd_conf_hashref($chksrvd_conf_hr);
}

sub save_chkservd_conf_hashref {
    my $chksrvd_conf_hr = shift;

    _ensure_chkservd_dir();

    delete @{$chksrvd_conf_hr}{ '', 0, "\n" };    # legacy cruft
    my $conf_text = join( "\n", map { $_ . ':' . int( $chksrvd_conf_hr->{$_} ) } sort keys %{$chksrvd_conf_hr} ) . "\n";

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Write');

    return 'Cpanel::FileUtils::Write'->can('overwrite')->( $Cpanel::Chkservd::Tiny::chkservd_conf, $conf_text, 0644 );
}

sub get_always_monitored {
    my %monitored = (
        'cpsrvd'         => 1,
        'queueprocd'     => 1,
        'dnsadmin'       => 1,
        'apache_php_fpm' => 1,
    );
    if ( !Cpanel::Server::Type::is_dnsonly() ) {
        $monitored{'cpanellogd'} = 1;
    }
    return \%monitored;
}

sub _ensure_chkservd_dir {
    if ( !-d $Cpanel::Chkservd::Config::chkservd_dir ) {
        return mkdir $Cpanel::Chkservd::Config::chkservd_dir, 0755;
    }

    return 1;
}

sub _get_skipped_services {
    my %skipped = (
        'eximstats'    => 1,
        'tailwatchd'   => 1,
        'cpanalyticsd' => 1,
    );

    require Cpanel::ServiceConfig::cpdavd;
    $skipped{'cpdavd'} = 1 if !Cpanel::ServiceConfig::cpdavd::is_needed();

    return \%skipped;
}

sub _update_driver_files {
    my %seen_alt_driver;

    _ensure_chkservd_dir();
    if ( opendir my $alt_dh, $alt_chkservd_dir ) {
        while ( my $driver_file = readdir $alt_dh ) {
            next if $driver_file =~ m/(?:^\.+$|\.conf$)/;
            next if $driver_file =~ m{\.rpm[^\.]+$};        # CPANEL-5659: light defense for .rpmorig, .rpmsave files until this can be refactored
            next if $driver_file =~ m{-cpanelsync$};        # CPANEL-5659: light defense for -cpanelsync files until this can be refactored

            my $driver_mtime     = ( stat( $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file ) )[9];
            my $alt_driver_mtime = ( stat( $alt_chkservd_dir . '/' . $driver_file ) )[9];
            next if !-f _;
            if ( !$driver_mtime || $driver_mtime != $alt_driver_mtime ) {
                system '/bin/cp', '-f', $alt_chkservd_dir . '/' . $driver_file, $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file;
                utime $alt_driver_mtime, $alt_driver_mtime, $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file;
                _logger()->info("Updated chkservd $driver_file driver from $alt_chkservd_dir.");
            }
            $seen_alt_driver{$driver_file} = 1;
        }
        closedir $alt_dh;
    }

    if ( opendir my $src_dh, $src_chkservd_dir ) {
        while ( my $driver_file = readdir $src_dh ) {
            next if $driver_file =~ m/(?:^\.+$|\.conf$)/ || $seen_alt_driver{$driver_file};
            next if $driver_file =~ m{\.rpm[^\.]+$};                                          # CPANEL-5659: light defense for .rpmorig, .rpmsave files until this can be refactored
            next if $driver_file =~ m{-cpanelsync$};                                          # CPANEL-5659: light defense for -cpanelsync files until this can be refactored

            my $driver_mtime     = ( stat( $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file ) )[9];
            my $src_driver_mtime = ( stat( $src_chkservd_dir . '/' . $driver_file ) )[9];
            next if !-f _;
            if ( !$driver_mtime || $driver_mtime != $src_driver_mtime ) {
                system '/bin/cp', '-f', $src_chkservd_dir . '/' . $driver_file, $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file;
                utime $src_driver_mtime, $src_driver_mtime, $Cpanel::Chkservd::Config::chkservd_dir . '/' . $driver_file;
                _logger()->info("Updated chkservd $driver_file driver from $src_chkservd_dir.");
            }
        }
        closedir $src_dh;
    }

    return 1;
}

my $logger;

sub _logger {
    return $logger if defined $logger;
    require Cpanel::Logger;
    return $logger ||= Cpanel::Logger->new();
}

1;

__END__

perl -MCpanel::Chkservd::Manage -MData::Dumper -e '$services = Cpanel::Chkservd::Manage::loadservices(); print Dumper $services; $monitored = Cpanel::Chkservd::Manage::getmonitored(); print Dumper $monitored; $eximport = Cpanel::Chkservd::geteximport(); print "Port: $eximport\n";'
