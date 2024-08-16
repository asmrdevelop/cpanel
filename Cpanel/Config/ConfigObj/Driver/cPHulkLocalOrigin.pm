package Cpanel::Config::ConfigObj::Driver::cPHulkLocalOrigin;

# cpanel - Cpanel/Config/ConfigObj/Driver/cPHulkLocalOrigin.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::ConfigObj::Driver::cPHulkLocalOrigin::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::cPHulkLocalOrigin::META::VERSION;

use Cpanel::LoadModule ();

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

    return $self->_update_setting(1);
}

sub disable {
    my ($self) = @_;
    return $self->_update_setting(0);
}

sub info {
    my ($self) = @_;
    return $self->meta()->abstract();
}

sub check {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Hulk::Load');
    my $conf = Cpanel::Config::Hulk::Load::loadcphulkconf();
    return $conf->{'is_enabled'} ? 1 : 0;
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Hulk::Conf');
    Cpanel::LoadModule::load_perl_module('Cpanel::Config::Hulk::Load');
    my $conf = Cpanel::Config::Hulk::Load::loadcphulkconf();
    return 1 unless $conf->{'is_enabled'};
    return 1 if defined $conf->{'username_based_protection_local_origin'} && $conf->{'username_based_protection_local_origin'} == $new_setting;

    my $interface = $self->interface();
    $conf->{'username_based_protection_local_origin'} = $new_setting;
    Cpanel::Config::Hulk::Conf::savecphulkconf($conf);
    $interface->schedule( [ 'restartsrv ' . 'cphulkd' ] ) or $interface->set_error('The system failed to schedule a restart for the cPHulk Daemon.');
    $interface->set_notice('Update cPHulk Configuration for Username-based Protection');
    return 1;
}

1;
