package Cpanel::FtpUtils::Config;

# cpanel - Cpanel/FtpUtils/Config.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile                   ();
use Cpanel::LoadModule                 ();
use Cpanel::Debug                      ();
use Cpanel::CPAN::Hash::Merge          ();
use Cpanel::FtpUtils::Server           ();
use Cpanel::FtpUtils::Config::Pureftpd ();
use Cpanel::FtpUtils::Config::Proftpd  ();

Cpanel::CPAN::Hash::Merge::set_behavior('RIGHT_PRECEDENT');

# Conf file provides basic settings
# Datastore provides overrides (set in WHM config interface)
#
# We would trust the conf file complely, but we can't guarante it will stay the same
# across upgrades, so the datastore takes precedence.
#
# Very similar to AdvConfig but without a template, and we only store the
# configurable settings in the datastore.

# This can be called as a normal function to determine which subclass to instantiate
sub determine_server_type {
    goto &Cpanel::FtpUtils::Server::determine_server_type;
}

# Really a dispatcher to the correct new()
sub new {
    return determine_server_type() eq 'proftpd' ? Cpanel::FtpUtils::Config::Proftpd->new() : Cpanel::FtpUtils::Config::Pureftpd->new();
}

# Instantiate the base class object
sub _init {
    my $class = shift;
    my $self  = {};

    return bless $self, $class;
}

sub get_display_name {
    my $self = shift;
    return $self->{'display_name'};
}

sub get_type {
    my $self = shift;
    return $self->{'type'};
}

sub get_config {
    my $self           = shift;
    my $check_defaults = shift;

    my $conf_hr = $self->read_settings_from_conf_file();

    my $configured_hr = $self->load_datastore();
    if ($configured_hr) {
        $conf_hr = Cpanel::CPAN::Hash::Merge::merge( $conf_hr, $configured_hr );
    }

    if ($check_defaults) {
        $self->check_for_unset_defaults($conf_hr);
    }
    return $conf_hr;
}

# compare the installed version with a specific version string
# returns 1 if the installed version meets the min_version requirement
# returns 0 if the installed version is older than the min_version
# returns -1 if it can't be determined
sub min_version {
    my $self        = shift;
    my $min_version = shift;
    return -1 unless $min_version;

    my $version_string = $self->get_version();
    if ($version_string) {
        my @min_parts       = split( /\./, $min_version );
        my @installed_parts = split( /\./, $version_string );
        foreach my $min (@min_parts) {
            my $installed = shift @installed_parts;
            return 0 unless ( defined $installed );
            $min       =~ s/\D+//g;
            $installed =~ s/\D+//g;
            if ( $min > $installed ) {
                return 0;
            }
            elsif ( $installed > $min ) {
                return 1;
            }
        }
        return 1;
    }
    else {
        return -1;
    }
}

sub load_datastore {
    my $self = shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::AdvConfig');
    return Cpanel::AdvConfig::load_app_conf( $self->{'datastore_name'}, 0 );
}

sub save_datastore {
    my $self    = shift;
    my $conf_hr = shift;
    Cpanel::LoadModule::load_perl_module('Cpanel::AdvConfig');
    return Cpanel::AdvConfig::save_app_conf( $self->{'datastore_name'}, 0, $conf_hr );
}

sub _parse_anon_arg {
    my $self          = shift;
    my $anon_arg      = shift;
    my $anonymous_ftp = 0;
    if ( defined $anon_arg ) {
        if ( $anon_arg =~ m/enable/i || $anon_arg eq '1' ) {
            $anonymous_ftp = 1;
        }
    }
    return $anonymous_ftp;
}

sub _slurp_config {
    my ($self) = @_;

    my $conf_file = $self->find_conf_file();

    # No need to lock since we always rename() into place
    my $contents = Cpanel::LoadFile::load($conf_file);
    if ( !length $contents ) {
        die "Empty FTP server configuration file: $conf_file";
    }

    return $contents;
}

# VIRTUAL -- Impliment in subclass
sub read_settings_from_conf_file {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub check_for_unset_defaults {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub find_conf_file {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub update_config {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub set_anon {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub find_executable {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub get_version {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

# VIRTUAL -- Impliment in subclass
sub get_port {
    my $self = shift;
    Cpanel::Debug::log_invalid('Unimplimented virtual method!');
    return;
}

1;
