package Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set;

# cpanel - Cpanel/Security/Authn/Provider/OpenIdConnectBase::Set.pm
#                                                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::Validate::OpenIdConnect ();

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set

=head1 DESCRIPTION

Do not call this module directly, it is dynamiclly
loaded from Cpanel::Security::Authn::Provider::OpenIdConnectBase
whe needed

=head2 set_client_configuration

This code is loaded on demand from Cpanel::Security::Authn::Provider::OpenIdConnectBase::set_client_configuration
Please see that function for documentation.

=cut

sub set_client_configuration {
    my ( $self, $config_hr ) = @_;

    Cpanel::Validate::OpenIdConnect::check_hashref_or_die($config_hr);

    my $config_fields = $self->get_configuration_fields();

    for my $key ( keys %$config_fields ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The configuration is missing the required parameter key “[_1]”.',                      [$key] ) if !length $config_hr->{$key};
        die Cpanel::Exception::create( 'InvalidParameter', 'The value of “[_1]” is not valid. Configuration field values are limited to strings.', [$key] ) if ref( $config_hr->{$key} );
    }

    for my $key ( keys %$config_hr ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The configuration key “[_1]” is not a valid configuration field for the provider “[_2]”.', [ $key, $self->_DISPLAY_NAME() ] ) if !defined $config_fields->{$key};
    }

    if ( !defined $config_hr->{redirect_uris} ) {
        $config_hr->{redirect_uris} = $self->get_default_redirect_uris();
    }

    $self->clear_well_known_configuration();

    return $self->_set_provider_client_configuration($config_hr);
}

=head2 set_display_configuration

This code is loaded on demand from Cpanel::Security::Authn::Provider::OpenIdConnectBase::set_display_configuration
Please see that function for documentation.

=cut

sub set_display_configuration {
    my ( $self, $service_name, $configurations ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name ) if length $service_name;

    $self->create_storage_directories_if_missing();

    my $provider_name = $self->get_provider_name();

    my $path = $self->_CUSTOM_DISPLAY_CONFIG_PATH( $provider_name, $service_name );

    my $display_configs = $self->get_display_configuration($service_name);

    for my $new_conf_key ( keys %$configurations ) {

        my $new_value = $configurations->{$new_conf_key};

        if ( !defined $display_configs->{$new_conf_key} ) {
            die Cpanel::Exception::create( 'InvalidParameter', "You can only update display configurations that already exist in the provider module, and the “[_1]” provider does not contain the “[_2]” display configuration parameter.", [ $provider_name, $new_conf_key ] );
        }

        #check select value types to ensure valid value

        if ( ( $new_conf_key eq 'textcolor' || $new_conf_key eq 'color' ) && !( $new_value =~ /^[0-9a-fA-F]{3,6}$/ ) ) {
            die Cpanel::Exception::create( 'InvalidParameter', "The display configuration parameter “[_1]” requires a hex color code without a Number symbol ([asis,#]). For example, [asis,FF0000] represents red.", [$new_conf_key] );
        }

        $display_configs->{$new_conf_key} = $new_value;
    }

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSON');
    my $transaction = Cpanel::Transaction::File::JSON->new(
        path        => $path,
        permissions => $Cpanel::Security::Authn::Config::DISPLAY_CONFIG_FILE_PERMS,
    );

    $transaction->set_data($display_configs);

    return $transaction->save_and_close_or_die();
}

1;
