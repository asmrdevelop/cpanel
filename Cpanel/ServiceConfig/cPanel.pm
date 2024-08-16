package Cpanel::ServiceConfig::cPanel;

# cpanel - Cpanel/ServiceConfig/cPanel.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.2';

use Cpanel::Logger              ();
use Cpanel::CPAN::Hash::Merge   ();
use Cpanel::AdvConfig           ();
use Cpanel::Config::LoadConfig  ();
use Cpanel::Config::FlushConfig ();
use Cpanel::SSL::Defaults       ();
Cpanel::CPAN::Hash::Merge::set_behavior('RIGHT_PRECEDENT');

sub new {
    my $class = shift;
    my $self  = $class->_init();
    $self->{'managed_settings'} = {
        'SSLCipherList' => {
            'name'    => 'SSL Cipher List',
            'setting' => 'SSL_cipher_list',
            'default' => Cpanel::SSL::Defaults::default_cipher_list(),
        },
        'SSLVersion' => {
            'name'    => 'SSL Protocol List',
            'setting' => 'SSL_version',
            'default' => Cpanel::SSL::Defaults::default_protocol_list( { 'type' => 'negative', 'delimiter' => ':', 'negation' => '!', separator => '_' } ),
        }
    };
    $self->{'remove_settings'} = {};

    return $self;
}

# Instantiate the base class object
sub _init {
    my $class  = shift;
    my $logger = Cpanel::Logger->new();
    my $self   = {
        'logger' => $logger,
    };

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

sub load_datastore {
    my $self       = shift;
    my $config_hr  = Cpanel::AdvConfig::load_app_conf( $self->{'datastore_name'}, 0 );
    my $configfile = $self->_config_file;
    my %ssl_conf;
    Cpanel::Config::LoadConfig::loadConfig( $configfile, \%ssl_conf, '=' );

    my $settings = $self->{'managed_settings'};
    foreach my $key ( keys %$settings ) {
        $config_hr->{$key} = $ssl_conf{ $settings->{$key}{'setting'} };
    }
    return $config_hr;
}

sub save_datastore {
    my $self    = shift;
    my $conf_hr = shift;
    return Cpanel::AdvConfig::save_app_conf( $self->{'datastore_name'}, 0, $conf_hr );
}

# Takes the same arguments as save_datastore.  Returns true if the arguments are
# syntactically valid values, false otherwise. ($@ contains the failure reason)
sub validate {
    my ( $self, $conf_hr ) = @_;
    my $config_hr = {};

    my $settings = $self->{'managed_settings'};
    foreach my $key ( keys %$settings ) {
        $config_hr->{ $settings->{$key}{'setting'} } = $conf_hr->{$key};
    }

    require IO::Socket::SSL;

    my $ctx = eval { IO::Socket::SSL::SSL_Context->new(%$config_hr) };
    return defined $ctx;
}

sub read_settings_from_conf_file {
    my $self = shift;
    return Cpanel::AdvConfig::load_app_conf( $self->{'datastore_name'} ) || {};
}

sub check_for_unset_defaults {
    my $self    = shift;
    my $conf_hr = shift;

    # Set defaults for configurable values we don't force elsewhere
    my $settings = $self->{'managed_settings'};
    foreach my $key ( keys %$settings ) {
        if ( !defined $conf_hr->{$key} ) {
            $conf_hr->{$key} = $settings->{$key}{'default'};
        }
    }
    return $conf_hr;
}

sub find_conf_file {
    my $self = shift;
    return;
}

sub _config_file {
    my $self = shift;
    return '/var/cpanel/conf/' . $self->{'datastore_name'} . '/ssl_socket_args';
}

sub update_config {
    my $self      = shift;
    my $save_conf = shift;

    $save_conf->{'VERSION'} = $VERSION;
    my $settings = $self->{'managed_settings'};
    foreach my $key ( keys %$settings ) {
        $save_conf->{$key} =~ s/[\r\n\f]//g;
    }
    Cpanel::AdvConfig::save_app_conf( $self->{'datastore_name'}, 0, $save_conf );
    my %ssl_conf;
    my $configfile = $self->_config_file;
    Cpanel::Config::LoadConfig::loadConfig( $configfile, \%ssl_conf, '=' );
    foreach my $key ( keys %$settings ) {
        $ssl_conf{ $settings->{$key}{'setting'} } = $save_conf->{$key};
    }
    Cpanel::Config::FlushConfig::flushConfig( $configfile, \%ssl_conf, '=' );
    return 1;
}

1;
