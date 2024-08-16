package Cpanel::Config::ConfigObj::Driver::Resetpass;

# cpanel - Cpanel/Config/ConfigObj/Driver/Resetpass.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::Resetpass::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::Resetpass::META::VERSION;

use Cpanel::Config::ConfigObj ();
use Cpanel::LoadModule        ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

sub init {
    my ( $class, $software_obj ) = @_;

    my $defaults = {
        'settings'      => {},
        'thirdparty_ns' => "",
    };
    my $self = $class->SUPER::base( $defaults, $software_obj );

    return $self;
}

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

# Testing stub; must implement per spec
sub enable {
    my ($self) = @_;
    return $self->_configFeature(1);
}

# Testing stub; must implement per spec
sub disable {
    my ($self) = @_;
    return $self->_configFeature(0);
}

sub check {
    return 1;
}

sub status {
    my ($self) = @_;
    my $current_setting = 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');

    my $cpconf_ref = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    $current_setting = $cpconf_ref->{'resetpass'};

    return $current_setting;
}

sub _configFeature {
    my ( $self, $new_value ) = @_;

    my $interface    = $self->interface();
    my $mod_string   = $new_value ? 'enabled' : 'disabled';
    my $meta_obj     = $self->meta();
    my $feature_name = $meta_obj->name('short');

    Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings');

    # do this to run the post actions
    my $result = Whostmgr::TweakSettings::set_value( 'Main', 'resetpass', $new_value, $self->status(), 1 );
    if ( !$result ) {
        $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Could not run Reset Password post-action.\n" );
        return;
    }
    $interface->set_notice("$feature_name has been $mod_string.");

    return 1;
}

1;
