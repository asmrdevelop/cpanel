package Whostmgr::API::1::Authentication;

# cpanel - Whostmgr/API/1/Authentication.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON                    ();
use Whostmgr::API::1::Utils         ();
use Cpanel::Exception               ();
use Cpanel::Security::Authn::Config ();

use constant NEEDS_ROLE => {
    get_available_authentication_providers   => undef,
    disable_failing_authentication_providers => undef,
    enable_authentication_provider           => undef,
    disable_authentication_provider          => undef,
    get_provider_client_configurations       => undef,
    set_provider_client_configurations       => undef,
    set_provider_display_configurations      => undef,
    get_provider_display_configurations      => undef,
    get_provider_configuration_fields        => undef,
};

=head1 NAME

Whostmgr::API::1::Authentication - WHM API functions for authentication. Used in Pluggable Authentication

=head2 get_available_authentication_providers()

=head3 Purpose

Returns an array of hashes contain information about the installed providers.
The contents of the hashes will vary per provider configuration

=head3 Output

    - 'providers' => [
          ...
          {
              ...
              'id'         => 'google',
              'whostmgrd_enabled'    => 1 || 0,
              'cpaneld_enabled'    => 1 || 0,
              'webmaild_enabled'    => 1 || 0,
              'configured' => 1 || 0,
              ...
          },
          {
              ...
              'id'         => 'microsoft',
              'whostmgrd_enabled'    => 1 || 0,
              'cpaneld_enabled'    => 1 || 0,
              'webmaild_enabled'    => 1 || 0,
              'configured' => 1 || 0,
              ...
          },
          ...
      ]

=cut

sub get_available_authentication_providers {
    my ( $args, $metadata ) = @_;

    my @authentication_modules = ();

    require Cpanel::Security::Authn::OpenIdConnect;
    my $modules = Cpanel::Security::Authn::OpenIdConnect::get_available_openid_connect_providers();

    my $enabled_providers = {};

    foreach my $service (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
        $enabled_providers->{$service} = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers($service);
    }

    foreach my $key ( keys %$modules ) {
        my $is_configured = $modules->{$key}->is_configured() ? 1 : 0;
        my $auth_module;
        foreach my $service (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
            my $display_config = $modules->{$key}->get_default_display_configuration($service);
            $auth_module->{"${service}_link"} = delete $display_config->{'link'};
            @{$auth_module}{ keys %$display_config } = @{$display_config}{ keys %$display_config };
            $auth_module->{'id'}                 = $key;
            $auth_module->{'configured'}         = $is_configured;
            $auth_module->{"${service}_enabled"} = $enabled_providers->{$service}->{$key} ? 1 : 0;
        }
        push @authentication_modules, $auth_module;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        'providers' => \@authentication_modules,
    };
}

=head2 disable_failing_authentication_providers()

=head3 Purpose

Disable, and report on, any authentication providers that are
enabled but fail to load.

=head3 Arguments

None.

=head3 Output

See C<Cpanel::Security::Authn::OpenIdConnect::disable_failing_providers()>.

=cut

sub disable_failing_authentication_providers {
    my ( $args, $metadata ) = @_;

    require Cpanel::Security::Authn::OpenIdConnect;

    my @disabled = Cpanel::Security::Authn::OpenIdConnect::disable_failing_providers();

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        payload => \@disabled,
    };
}

=head2 enable_authentication_provider()

=head3 Purpose

Enables a specific provider for use in a specific service.

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to enable a providers on
            'provider_id' => 'google' - which provider to enable
        }

=head3 Output

=cut

sub enable_authentication_provider {
    my ( $args, $metadata ) = @_;
    my $service_name = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id  = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    Cpanel::Security::Authn::OpenIdConnect::enable_openid_connect_provider( $service_name, $provider_id );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 disable_authentication_provider()

=head3 Purpose

Disables a specific provider for use in a specific service.

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to disable a providers on
            'provider_id' => 'google' - which provider to disable
        }

=head3 Output

=cut

sub disable_authentication_provider {
    my ( $args, $metadata ) = @_;
    my $service_name = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id  = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    Cpanel::Security::Authn::OpenIdConnect::disable_openid_connect_provider( $service_name, $provider_id );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return;
}

=head2 get_provider_client_configurations()

=head3 Purpose

Returns the set configurations for a specific provider.

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to get provider configurations for
            'provider_id' => 'google' - which provider to get configurations for
        }

=head3 Output

    - 'client_configurations' => {
            'client_id'    => 'blargh',
            'cient_secret' => 'blargh',
        }

=cut

sub get_provider_client_configurations {
    my ( $args, $metadata ) = @_;
    my $service_name = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id  = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    my $provider       = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service_name, $provider_id );
    my $configurations = $provider->get_client_configuration();

    # May be undef if the client isn't already configured, but we should show the
    # redirect URIs for ease of configuration.
    if ( !$configurations ) {
        $configurations = { 'redirect_uris' => $provider->get_default_redirect_uris() };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {
        'client_configurations' => $configurations,
    };
}

=head2 set_provider_client_configurations()

=head3 Purpose

sets the specific client configurations for a provider

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to set provider configurations for
            'provider_id' => 'google' - which provider to set configurations for
            'configurations' => '{"field":"value"}' - JSON encoded string of field values for a specific provider
        }

=head3 Output

=cut

sub set_provider_client_configurations {

    my ( $args, $metadata ) = @_;
    my $service_name   = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id    = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );
    my $config_str     = Whostmgr::API::1::Utils::get_required_argument( $args, 'configurations' );
    my $configurations = Cpanel::JSON::Load($config_str);

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    my $provider = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service_name, $provider_id );

    $provider->set_client_configuration($configurations);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {};
}

=head2 set_provider_display_configurations()

=head3 Purpose

sets the specific display configurations for a provider

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to set provider configurations for
            'provider_id' => 'google' - which provider to set configurations for
            'configurations' => '{"field":"value"}' - JSON encoded string of field values for a specific provider
        }

=head3 Output

=cut

sub set_provider_display_configurations {

    my ( $args, $metadata ) = @_;
    my $service_name   = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id    = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );
    my $config_str     = Whostmgr::API::1::Utils::get_required_argument( $args, 'configurations' );
    my $configurations = Cpanel::JSON::Load($config_str);

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    my $provider = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service_name, $provider_id );

    $provider->set_display_configuration( $service_name, $configurations );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {};
}

=head2 get_provider_display_configurations()

=head3 Purpose

gets the specific display configurations for a provider

=head3 Arguments

    - $args - {
            'provider_id' => 'google' - which provider to set configurations for
        }

=head3 Output

    - @configurations - [
            {
              "provider_name" => "google",
              "textcolor" => "FFFFFF",
              "display_name" => "Google",
              "icon" => "PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMiIgaGVpZ2h0PSIxNCIgdmlld0JveD0iMCAwIDIyIDE0Ij48ZyBmaWxsPSIjZmZmIiBmaWxsLXJ1bGU9ImV2ZW5vZGQiPjxwYXRoIGQ9Ik03IDZ2Mi40aDMuOTdjLS4xNiAxLjAzLTEuMiAzLjAyLTMuOTcgMy4wMi0yLjM5IDAtNC4zNC0xLjk4LTQuMzQtNC40MlM0LjYxIDIuNTggNyAyLjU4YzEuMzYgMCAyLjI3LjU4IDIuNzkgMS4wOGwxLjktMS44M0MxMC40Ny42OSA4Ljg5IDAgNyAwIDMuMTMgMCAwIDMuMTMgMCA3czMuMTMgNyA3IDdjNC4wNCAwIDYuNzItMi44NCA2LjcyLTYuODQgMC0uNDYtLjA1LS44MS0uMTEtMS4xNkg3ek0yMiA2aC0yVjRoLTJ2MmgtMnYyaDJ2MmgyVjhoMiIvPjwvZz48L3N2Zz4=",
              "service" => "whostmgrd",
              "documentation_url" => "https://developers.google.com/identity/protocols/OpenIDConnect",
              "label" => "Log in via Google",
              "icon_type" => "image/svg+xml",
              "link" => "https://server.example.com:2087/openid_connect/google",
              "color" => "dd4b39"
            },
            ...
    ]

=cut

sub get_provider_display_configurations {
    my ( $args, $metadata ) = @_;
    my $provider_id = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );

    my @configurations;

    require Cpanel::Security::Authn::OpenIdConnect;

    foreach my $service (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
        my $provider       = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service, $provider_id );
        my $display_config = $provider->get_display_configuration($service);
        $display_config->{"service"} = $service;
        push @configurations, $display_config;
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { "configurations" => \@configurations };
}

=head2 get_provider_configuration_fields()

=head3 Purpose

gets the configurable fields for a provider and their descriptions

=head3 Arguments

    - $args - {
            'service_name' => 'cpaneld' - which service to get provider configurations fields for
            'provider_id' => 'google' - which provider to get configurations fields for
        }

=head3 Output

    - 'configuration_fields' => {
        'field_key' => {           - maps to the specific client configuration
            'label'       => '',   - display label of the field
            'description' => '',   - tool tip description of the field
            'value'       => '',   - current set value
        },
        ...
    }

=cut

sub get_provider_configuration_fields {
    my ( $args, $metadata ) = @_;
    my $service_name = Whostmgr::API::1::Utils::get_required_argument( $args, 'service_name' );
    my $provider_id  = Whostmgr::API::1::Utils::get_required_argument( $args, 'provider_id' );

    if ( !grep { $service_name eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        die Cpanel::Exception->create( "Currently, only [list_and_quoted,_1] can use External Authentication.", [ \@Cpanel::Security::Authn::Config::ALLOWED_SERVICES ] );
    }

    require Cpanel::Security::Authn::OpenIdConnect;
    my $provider             = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $service_name, $provider_id );
    my $configuration_fields = $provider->get_configuration_fields();

    my @results = ();
    foreach my $config_key ( keys %$configuration_fields ) {

        my $config = $configuration_fields->{$config_key};

        push @results,
          {
            "field_id" => $config_key,
            %$config
          };

    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return {
        'configuration_fields' => \@results,
    };
}

1;
