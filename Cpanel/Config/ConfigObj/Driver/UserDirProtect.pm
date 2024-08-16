package Cpanel::Config::ConfigObj::Driver::UserDirProtect;

# cpanel - Cpanel/Config/ConfigObj/Driver/UserDirProtect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::ConfigObj::Driver::UserDirProtect::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::UserDirProtect::META::VERSION;

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

sub enable {
    my ($self) = @_;

    if ( !$self->_update_setting(1) ) {
        $self->interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Could not enable " . $self->meta->name('short') . "\n" );
        return 0;
    }
    else {
        $self->interface->set_notice( $self->meta->name('short') . " has been enabled.\n" );
        return 1;
    }
}

sub disable {
    my ($self) = @_;
    if ( !$self->_update_setting(0) ) {
        $self->interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Could not disable " . $self->meta->name('short') . "\n" );
        return 0;
    }
    else {
        $self->interface->set_notice( $self->meta->name('short') . " has been disabled.\n" );
        return 1;
    }
}

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

sub check {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return $cpconf->{'userdirprotect'};
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    Cpanel::LoadModule::load_perl_module('Whostmgr::TweakSettings');

    if ( !Whostmgr::TweakSettings::set_value( 'Main', 'userdirprotect', $new_setting ) ) {
        return 0;
    }

    return 1;
}

1;
