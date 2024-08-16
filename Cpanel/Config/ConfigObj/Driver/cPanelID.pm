package Cpanel::Config::ConfigObj::Driver::cPanelID;

# cpanel - Cpanel/Config/ConfigObj/Driver/cPanelID.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

*VERSION = \$Cpanel::Config::ConfigObj::Driver::cPanelID::META::VERSION;

use Cpanel::Exception         ();
use Cpanel::LoadModule        ();
use Cpanel::Config::ConfigObj ();
use Try::Tiny;

# This driver implements v1 spec
use parent qw(Cpanel::Config::ConfigObj::Interface::Config::v1);

our $SERVICE_NAME  = 'cpaneld';
our $PROVIDER_NAME = 'cpanelid';

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
    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::OpenIdConnect');
    my $enabled_providers = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers($SERVICE_NAME);
    return $enabled_providers->{$PROVIDER_NAME} ? 1 : 0;
}

sub _update_setting {
    my ( $self, $new_setting ) = @_;

    my $old_setting = $self->check();

    my $interface = $self->interface();
    my $action    = ( $new_setting == 1 ) ? 'enabled' : 'disabled';

    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::OpenIdConnect');
    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::Config');

    # ensure that if no value was previously set, set it now (even for 'disable'
    #  which is the implied state) as this is occurring due to an explict
    #  user request
    if ( !defined $old_setting || $new_setting != $old_setting ) {
        my $err;
        try {
            foreach my $service (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
                if ($new_setting) {
                    Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service, $PROVIDER_NAME )->set_client_configuration( { 'client_id' => 'auto', 'client_secret' => 'auto' } );
                    Cpanel::Security::Authn::OpenIdConnect::enable_openid_connect_provider( $service, $PROVIDER_NAME );

                }
                else {
                    Cpanel::Security::Authn::OpenIdConnect::disable_openid_connect_provider( $service, $PROVIDER_NAME );
                }
            }
        }
        catch {
            $err = $_;
        };
        if ($err) {
            $interface->set_error( Cpanel::Config::ConfigObj::E_ERROR, "cPanelID could not be $action because of an error: " . Cpanel::Exception::get_string($err), __LINE__ );
            return undef;
        }
        $interface->set_notice("cPanelID has been $action.");

        return 1;

    }
    $interface->set_notice("cPanelID is already $action.");
    return 1;
}

1;
