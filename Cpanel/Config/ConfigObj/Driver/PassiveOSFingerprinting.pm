package Cpanel::Config::ConfigObj::Driver::PassiveOSFingerprinting;

# cpanel - Cpanel/Config/ConfigObj/Driver/PassiveOSFingerprinting.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Config::ConfigObj::Driver::PassiveOSFingerprinting::META ();
*VERSION = \$Cpanel::Config::ConfigObj::Driver::PassiveOSFingerprinting::META::VERSION;

use Cpanel::Config::ConfigObj ();
use Cpanel::LoadModule        ();

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

our $SERVICE_NAME = 'p0f';

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

    Cpanel::LoadModule::load_perl_module('Cpanel::Services::Enabled');

    return Cpanel::Services::Enabled::is_enabled($SERVICE_NAME);
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;
    Cpanel::LoadModule::load_perl_module('Cpanel::Services::Enabled');

    my $old_setting = Cpanel::Services::Enabled::is_enabled($SERVICE_NAME);

    my $interface = $self->interface();
    my $action    = ( $new_setting == 1 ) ? 'enabled' : 'disabled';

    # ensure that if no value was previously set, set it now (even for 'disable'
    #  which is the implied state) as this is occurring due to an explict
    #  user request
    if ( !defined $old_setting || $new_setting != $old_setting ) {
        Cpanel::LoadModule::load_perl_module('Whostmgr::Services');

        my ( $service_set_status, @service_set_messages );
        if ($new_setting) {
            ( $service_set_status, @service_set_messages ) = Whostmgr::Services::enable($SERVICE_NAME);
            if ($service_set_status) {
                Cpanel::LoadModule::load_perl_module('Cpanel::Chkservd::Manage');
                Cpanel::Chkservd::Manage::enable($SERVICE_NAME);

                # No need to schedule a restart as Whostmgr::Services::enable does that
            }
        }
        else {
            ( $service_set_status, @service_set_messages ) = Whostmgr::Services::disable($SERVICE_NAME);
        }
        my $combined_service_set_message = join( ' ', @service_set_messages );
        if ($service_set_status) {
            $interface->set_notice( "Passive OS Fingerprinting has been $action: " . $combined_service_set_message );
            return 1;
        }

        $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "Passive OS Fingerprinting could not be $action because of an error: " . $combined_service_set_message, __LINE__ );
    }
    else {
        $interface->set_notice("Passive OS Fingerprinting is already $action.");
        return 1;
    }
    return;
}

1;
