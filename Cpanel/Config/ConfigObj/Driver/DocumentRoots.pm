package Cpanel::Config::ConfigObj::Driver::DocumentRoots;

# cpanel - Cpanel/Config/ConfigObj/Driver/DocumentRoots.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule ();

*VERSION = \$Cpanel::Config::ConfigObj::Driver::DocumentRoots::META::VERSION;

# This driver implements v1 spec
use parent qw{Cpanel::Config::ConfigObj::Interface::Config::v1};

# Testing stub; must implement per spec
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

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard');

    my $cpconf = Cpanel::Config::CpConfGuard->new();
    $cpconf->set( 'publichtmlsubsonly', 1 );
    return $cpconf->save();
}

# Testing stub; must implement per spec
sub disable {
    my ($self) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::CpConfGuard');

    my $cpconf = Cpanel::Config::CpConfGuard->new();
    $cpconf->set( 'publichtmlsubsonly', 0 );
    return $cpconf->save();
}

# Testing stub; must implement per spec
sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

sub status {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::LoadCpConf');
    return Cpanel::Config::LoadCpConf::loadcpconf_not_copy()->{'publichtmlsubsonly'};
}

1;
