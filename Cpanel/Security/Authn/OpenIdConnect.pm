package Cpanel::Security::Authn::OpenIdConnect;

# cpanel - Cpanel/Security/Authn/OpenIdConnect.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
#IMPORTANT!! GLOSSARY OF TERMS:
#
#   “available” - means a module is present on the system, nothing more
#
#   “enabled” - means the administrator has allowed the module to be used
#
#   “configured” - means the administrator has saved the information
#       needed to have the module communicate with the provider.
#       (For an OpenID Connect provider, for example, this means the
#       Client ID and Client Secret.)
#
#It’s not very useful to have (enabled && !configured), but having
#(!enabled && configured) allows storing configuration data while the
#authn provider is (temporarily?) disabled.
#
#   “service name” - For a list of allowed service names, see
#       @Cpanel::Security::Authn::Config::ALLOWED_SERVICES.
#
#   “provider name” - that which is given by the _PROVIDER_NAME() method
#       of the authn provider module. Should be all 7-bit ASCII, lower case.
#----------------------------------------------------------------------

use strict;

use Try::Tiny;

use Cpanel::ArrayFunc::Uniq               ();
use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::LoadModule                    ();
use Cpanel::Security::Authn::Config       ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::OpenIdConnect       ();

#used in tests
our $_PROVIDER_BASE_CLASS = 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

###########################################################################
#
# Method:
#   disable_failing_providers
#
# Description:
#   Disables any provider modules that do not load or do not subclass the
#   $_PROVIDER_BASE_CLASS.
#
# Parameters: (none)
#
# Exceptions:
#   - anything Cpanel::Transaction::File::JSONReader throws
#
# Returns:
#   A list of hashes, one for each disabled provider, e.g.:
#       {
#           provider_name       => 'microsoft_live',
#           provider_namespace  => 'Cpanel::Security::Authn::Provider::MicrosoftLive',
#           provider_failure    => '...',
#           disabled_services   => [ 'cpaneld' ],
#           failures_to_disable => [
#               {
#                   service_name => 'whostmgrd',
#                   failure => '...',   #errors are strings presently
#               },
#           ],
#       }
#
sub disable_failing_providers {
    Cpanel::Context::must_be_list();

    my %provider_service_to_disable;

    my %provider_module;

    my %provider_error;

    for my $svc (@Cpanel::Security::Authn::Config::ALLOWED_SERVICES) {
        my $svc_provider_data = get_enabled_openid_connect_providers($svc);

        for my $provider_name ( keys %$svc_provider_data ) {

            #Check this module for load errors.
            if ( !$provider_module{$provider_name} ) {
                $provider_module{$provider_name} = $svc_provider_data->{$provider_name};

                try {
                    _load_provider_module_and_check( $provider_module{$provider_name} );
                }
                catch {
                    $provider_error{$provider_name} = $_;
                };
            }

            #If the module failed to load, then make a note
            #to disable it from this service.
            if ( $provider_error{$provider_name} ) {
                $provider_service_to_disable{$provider_name} ||= [];
                push @{ $provider_service_to_disable{$provider_name} }, $svc;
            }
        }
    }

    my @disabled;

    for my $provider_name ( keys %provider_service_to_disable ) {
        my ( @services_disabled, @errors );

        my %disable = (
            provider_name       => $provider_name,
            provider_namespace  => $provider_module{$provider_name},
            provider_failure    => Cpanel::Exception::get_string( $provider_error{$provider_name} ),
            disabled_services   => \@services_disabled,
            failures_to_disable => \@errors,
        );

        for my $svc ( @{ $provider_service_to_disable{$provider_name} } ) {
            try {
                disable_openid_connect_provider( $svc, $provider_name );
                push @services_disabled, $svc;
            }
            catch {
                push @errors,
                  {
                    service_name => $svc,
                    failure      => Cpanel::Exception::get_string($_),
                  };
            };
        }

        push @disabled, \%disable;
    }

    return @disabled;
}

###########################################################################
#
# Method:
#   get_enabled_openid_connect_providers
#
# Description:
#   This function gets all the enabled openid connect providers for a service.
#
#   NB: The return from this function will be a subset of the return from
#   get_available_openid_connect_providers.
#
# Parameters:
#   $service_name - The service name to get the enabled openid connect providers for.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   A hashref of enabled providers, given as provider name => package namespace.
#   For example:
#
#   {
#       cpanelid        => 'Cpanel::Security::Authn::Provider::CpanelId',
#       microsoft_live  => 'Cpanel::Security::Authn::Provider::MicrosoftLive',
#   }
#
sub get_enabled_openid_connect_providers {
    my ($service_name) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name );

    create_storage_directories_if_missing();

    my $service_config_file = $Cpanel::Security::Authn::Config::OIDC_AUTHENTICATION_CONFIG_DIR . '/' . $service_name;

    my $providers = {};
    if ( -e $service_config_file ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $service_config_file );
        $providers = $reader_transaction->get_data();
        return {} unless ref $providers eq 'HASH';
    }

    return $providers;
}

###########################################################################
#
# Method:
#   get_available_openid_connect_providers
#
# Description:
#   This function gets all the available openid connect providers on the system.
#
#   NB: The return from this function will be a superset of the return from
#   get_enabled_openid_connect_providers.
#
# Parameters:
#   None.
#
# Exceptions:
#   Anything Cpanel::LoadModule::Name::get_module_names_from_directory can throw.
#
# Returns:
#   A hashref of enabled providers, given as provider name => package namespace.
#   For example:
#
#   {
#       cpanelid        => 'Cpanel::Security::Authn::Provider::CpanelId',
#       microsoft_live  => 'Cpanel::Security::Authn::Provider::MicrosoftLive',
#   }
#
sub get_available_openid_connect_providers {

    require Cpanel::LoadModule::Name;
    my @providers = map { $_ eq 'OpenIdConnectBase' ? () : 'Cpanel::Security::Authn::Provider::' . $_ } Cpanel::ArrayFunc::Uniq::uniq(
        map {    #
            Cpanel::LoadModule::Name::get_module_names_from_directory( $_ . $Cpanel::Security::Authn::Config::PROVIDER_MODULE_DIR )    #
        } @Cpanel::Security::Authn::Config::PROVIDER_MODULE_SEARCH_ROOTS    #
    );

    my $providers_hr = {};
    for my $provider_ns (@providers) {
        next if !_load_provider_module_and_check_and_catch($provider_ns);

        my $name = $provider_ns->get_provider_name();

        $providers_hr->{$name} = $provider_ns;
    }

    return $providers_hr;
}

###########################################################################
#
# Method:
#   get_enabled_and_configured_openid_connect_providers
#
# Description:
#   This function gets all the enabled and configured openid connect providers on the system.
#
#   NB: The return from this function will be a subset of the return from
#   get_enabled_openid_connect_providers.
#
# Parameters:
#   $service_name - The service name to get the enabled and configured openid connect providers for.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   A hashref of enabled providers, given as provider name => package namespace.
#   For example:
#
#   {
#       cpanelid        => 'Cpanel::Security::Authn::Provider::CpanelId',
#       microsoft_live  => 'Cpanel::Security::Authn::Provider::MicrosoftLive',
#   }
#
sub get_enabled_and_configured_openid_connect_providers {
    my ($service_name) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name );

    my $enabled_providers = get_enabled_openid_connect_providers($service_name);

    my $providers_hr = {};
    for my $provider_name ( keys %$enabled_providers ) {
        my $provider_ns = $enabled_providers->{$provider_name};

        next if !_load_provider_module_and_check_and_catch($provider_ns);
        next if !$provider_ns->is_configured();

        my $name = $provider_ns->get_provider_name();
        $providers_hr->{$name} = $provider_ns;
    }

    return $providers_hr;
}

###########################################################################
#
# Method:
#   enable_openid_connect_provider
#
# Description:
#   This function enables an openid connect provider for a service.
#
# Parameters:
#   $service_name - The service name to enable openid connect provider for. Such as 'cpaneld'.
#   $provider     - The name of the provider to enable for the supplied service. Such as 'cpanelid'.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Validate::AuthProvider::check_provider_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   1
#
sub enable_openid_connect_provider {
    my ( $service_name, $provider ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_and_provider_or_die( \$service_name, \$provider );

    create_storage_directories_if_missing();

    my $transaction = _get_service_config_transaction($service_name);
    my $providers   = $transaction->get_data();

    # Initialize data if needed
    $providers = {} if ref $providers ne 'HASH';

    $providers->{$provider} = _get_provider_ns($provider);

    $transaction->set_data($providers);

    $transaction->save_and_close_or_die();
    $transaction = undef;

    return 1;
}

###########################################################################
#
# Method:
#   disable_openid_connect_provider
#
# Description:
#   This function disables an openid connect provider for a service.
#
# Parameters:
#   $service_name - The service name to disable openid connect provider for.
#   $provider     - The name of the provider to disable for the supplied service.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Validate::AuthProvider::check_provider_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   1
#
sub disable_openid_connect_provider {
    my ( $service_name, $provider ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_and_provider_or_die( \$service_name, \$provider );

    create_storage_directories_if_missing();

    my $transaction = _get_service_config_transaction($service_name);
    my $providers   = $transaction->get_data();

    # Initialize data if needed
    $providers = {} if ref $providers ne 'HASH';

    delete $providers->{$provider};

    $transaction->set_data($providers);

    $transaction->save_and_close_or_die();
    $transaction = undef;

    return 1;
}

###########################################################################
#
# Method:
#   get_openid_provider
#
# Description:
#   This function returns the openid provider object for a specific service.
#
# Parameters:
#   $requested_provider_name - The name of the provider to retrieve an object for.
#   $service_name            - The service name to retrieve a provider object for.
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Validate::AuthProvider::check_provider_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#   Anything Cpanel::LoadModule::load_perl_module can throw.
#
# Returns:
#   The requested provider object for the service.
#
sub get_openid_provider {
    my ( $service_name, $requested_provider_name ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_and_provider_or_die( \$service_name, \$requested_provider_name );

    # This loads the module and returns the provider package class name
    my $provider_ns = _get_provider_ns_and_load( $requested_provider_name, $service_name );

    return $provider_ns->new( 'service_name' => $service_name );
}

###########################################################################
#
# Method:
#   get_enabled_openid_provider_display_configurations
#
# Description:
#   This function returns the display configurations for enabled and configured openid providers for a service
#
# Parameters:
#   $service_name            - The service name to the display configurations for. Such as 'cpaneld'
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   An arrayref of hashrefs. Each hashref is the return of a module’s
#   get_display_configurations() method.
#
sub get_enabled_openid_provider_display_configurations {
    my ($service_name) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name );

    my $enabled_providers = get_enabled_and_configured_openid_connect_providers($service_name);
    my $providers         = [ map { $_->get_display_configuration($service_name) } values %$enabled_providers ];

    my @sorted_providers = sort { CORE::fc( $a->{display_name} ) cmp CORE::fc( $b->{display_name} ) } @$providers;
    return \@sorted_providers;
}

###########################################################################
#
# Method:
#   set_openid_provider_client_config
#
# Description:
#   This function sets the client configuration for a specific provider.
#
# Parameters:
#   $provider      - The name of the provider to set the configuration for. Such as 'cpanelid'.
#   $client_config - A hashref representing the configuration for the provider fitting the form:
#                    {
#                       client_id     => The client ID obtained during setting up the authorization link with the authority server.
#                       client_secret => The client secret obtained during setting up the authorization link with the authority server.
#                    }
#
# Exceptions:
#   Anything Cpanel::Validate::OpenIdConnect::check_service_name_or_die can throw.
#   Anything Cpanel::Validate::OpenIdConnect::check_hashref_or_die can throw.
#   Anything Cpanel::Transaction::File::JSON* can throw.
#
# Returns:
#   An empty list.
#
sub set_openid_provider_client_config {
    my ( $provider, $client_config ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_provider_or_die( \$provider );
    Cpanel::Validate::OpenIdConnect::check_hashref_or_die( $client_config, 'client_config' );

    # This loads the module and returns the provider package class name
    my $provider_ns = _get_provider_ns_and_load($provider);

    # More validation will be done in the specific provider. See Cpanel::Security::Authn::OpenIdConnectBase::set_client_configuration
    $provider_ns->set_client_configuration($client_config);

    return;
}

sub _get_service_config_transaction {
    my ($service_name) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSON');
    my $service_config_file = $Cpanel::Security::Authn::Config::OIDC_AUTHENTICATION_CONFIG_DIR . '/' . $service_name;
    return Cpanel::Transaction::File::JSON->new( path => $service_config_file, permissions => 0644 );
}

# This returns the provider module namespace
sub _get_provider_ns {
    my ($requested_provider_name) = @_;

    my $configured_providers_hr = get_available_openid_connect_providers();

    my $provider_ns = $configured_providers_hr->{$requested_provider_name};
    if ( !length $provider_ns ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The requested provider “[_1]” is not valid.', [$requested_provider_name] );
    }

    return $provider_ns;

}

# This loads the module and returns the module namespace
sub _get_provider_ns_and_load {
    my ( $requested_provider_name, $service_name ) = @_;

    $service_name ||= 'cpaneld';

    my $provider_ns = _get_provider_ns($requested_provider_name);

    return _load_provider_module($provider_ns);
}

# This loads the module by module namespace
sub _load_provider_module_and_check_and_catch {
    my ($provider_ns) = @_;

    # We also don't want cpsrvd eating our load error here if the module doesn't exist
    local $SIG{__DIE__};

    # We want this to be speedy, so eval instead of try
    local $@;
    return 1 if eval { _load_provider_module_and_check($provider_ns); 1 };

    _logger()->warn("The system cannot use the OpenID Connect provider module “$provider_ns”: $@");
    return 0;
}

sub _load_provider_module_and_check {
    my ($provider_ns) = @_;

    _load_provider_module($provider_ns);

    if ( !$provider_ns->isa($_PROVIDER_BASE_CLASS) ) {
        die Cpanel::Exception->create( 'The provider module “[_1]” must extend the module “[_2]”.', [ $provider_ns, $_PROVIDER_BASE_CLASS ] );
    }

    return 1;
}

# This loads the module by module namespace
sub _load_provider_module {
    my ($provider_ns) = @_;

    require Cpanel::LoadModule::Custom;
    Cpanel::LoadModule::Custom::load_perl_module($provider_ns);

    return $provider_ns;
}

sub _load_modules {
    my (@modules) = @_;
    for my $module (@modules) {
        Cpanel::LoadModule::load_perl_module($module);
    }
    return;
}

sub create_storage_directories_if_missing {
    return if $> != 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

    my $target_perms = $Cpanel::Security::Authn::Config::CLIENT_CONFIG_DIR_PERMS;

    my @dir_consts = qw(
      CPANEL_AUTHN_CONFIG_DIR
      OIDC_AUTHENTICATION_CONFIG_DIR
    );

    for my $dir (@dir_consts) {
        $dir = ${ *{ $Cpanel::Security::Authn::Config::{$dir} }{'SCALAR'} };

        Cpanel::Mkdir::ensure_directory_existence_and_mode(
            $dir,
            $target_perms,
        );
    }

    return;
}

my $logger;

sub _logger {
    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    return $logger ||= Cpanel::Logger->new();
}

1;
