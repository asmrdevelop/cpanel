package Cpanel::Security::Authn::Provider::OpenIdConnectBase;

# cpanel - Cpanel/Security/Authn/Provider/OpenIdConnectBase.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception                      ();
use Cpanel::JSON                           ();
use Cpanel::LoadModule                     ();
use Cpanel::Services::Ports                ();
use Cpanel::Security::Authn::Config        ();
use Cpanel::Security::Authn::OpenIdConnect ();
use Cpanel::Transaction::File::JSONReader  ();
use Cpanel::Validate::OpenIdConnect        ();
use Cpanel::Locale::Lazy 'lh';

use Try::Tiny;

############################################################################################
# Override methods, please override these in child classes if needed
############################################################################################

#-------------------------------------------------------------------------------------------
# Required override methods. These methods need to be overridden.
#-------------------------------------------------------------------------------------------

# The name to use in the interface or anytime the name of the provider needs to be displayed to a user
sub _DISPLAY_NAME { die Cpanel::Exception::create( 'FunctionNotImplemented', [ name => '_DISPLAY_NAME' ] ); }

# The system name of the provider. This should be unique amongst all the providers on the system and should be in lower case.
sub _PROVIDER_NAME { die Cpanel::Exception::create( 'FunctionNotImplemented', [ name => '_PROVIDER_NAME' ] ); }

# The well-known configuration URI for the provider implementation.
# cf. http://tools.ietf.org/html/rfc5785
sub _WELL_KNOWN_CONFIG_URI { die Cpanel::Exception::create( 'FunctionNotImplemented', [ name => '_WELL_KNOWN_CONFIG_URI' ] ); }

#-------------------------------------------------------------------------------------------
# Optional override methods. These methods are suggested to override, but are optional.
#-------------------------------------------------------------------------------------------

# The color the button for the provider should be in the UI in RRGGBB format.
sub _BUTTON_COLOR { return 'cccccc'; }

# The base-64 encoded image to use on the button in the UI.
sub _BUTTON_ICON { return ''; }

sub _BUTTON_ICON_TYPE { return 'image/svg+xml' }

# The text to use on the button in the UI.
sub _BUTTON_LABEL {
    my ($self) = @_;

    my $disp_name = $self->_DISPLAY_NAME() or die "Need a _DISPLAY_NAME!";

    return lh()->maketext( 'Log in via [_1]', $disp_name );
}

# The color of the text to use on the button in the UI in RRGGBB format.
sub _BUTTON_TEXT_COLOR { return '000000'; }

# The URL to the documentation for the provider implementation.
sub _DOCUMENTATION_URL { return 'http://openid.net/developers/specs/'; }

#-------------------------------------------------------------------------------------------
# Optional configuration override. These methods may need to be overridden depending on your chosen
# OpenID Connect implementation
#-------------------------------------------------------------------------------------------

# The return of this function indicates if the ID Token received from the authentication server should be verified after being retrieved from the session.
# This should be overridden if your provider does not support verification (ie. isn't really Open ID Connect)
sub _CAN_VERIFY { return 1; }

# This function returns the necessary configuration information for the provider module.
sub _CONFIG {
    my ($self) = @_;

    my $client_config     = $self->get_client_configuration();
    my $well_known_config = $self->get_well_known_configuration();

    return {
        'id'               => $client_config->{client_id},
        'secret'           => $client_config->{client_secret},
        'authorize_uri'    => $well_known_config->{authorization_endpoint},
        'access_token_uri' => $well_known_config->{token_endpoint},
        'user_info_uri'    => $well_known_config->{userinfo_endpoint},
        'redirect_uris'    => $client_config->{redirect_uris},
    };
}

# This function returns the required configuration fields for the provider module. This should be overridden if your provider requires different information.
sub _CONFIG_FIELDS {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return {
        'client_id' => {
            'label'         => 'Client ID',
            'description'   => 'The ID of the Client',
            'value'         => $client_config->{client_id},
            'display_order' => 0,
        },
        'client_secret' => {
            'label'         => 'Client Secret',
            'description'   => 'The Secret of the Client',
            'value'         => $client_config->{client_secret},
            'display_order' => 1,
        },
    };
}

# This function returns the assembled display information for the provider module. This should be overridden if you require different display information
sub _DISPLAY_CONFIG {
    my ($self) = @_;

    my $icon = $self->_BUTTON_ICON();
    $icon =~ tr<\n><>d;

    # Get an SSL base URI for the service to use as the base of the external authn link
    return {
        'label'     => scalar $self->_BUTTON_LABEL(),
        'link'      => '/openid_connect/' . scalar $self->get_provider_name(),
        'color'     => scalar $self->_BUTTON_COLOR(),
        'textcolor' => scalar $self->_BUTTON_TEXT_COLOR(),
        $icon ? ( 'icon' => $icon ) : (),
        'icon_type'         => scalar $self->_BUTTON_ICON_TYPE(),
        'display_name'      => scalar $self->_DISPLAY_NAME(),
        'provider_name'     => scalar $self->get_provider_name(),
        'documentation_url' => scalar $self->get_documentation_url(),
    };
}

# This function returns the signing key for HMAC SHA signatures. This should be overridden if your provider needs a different key for the signature verification.
sub _GET_SECRET_BASED_SIGNING_KEY_PLAINTEXT {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return $client_config->{client_secret};
}

# This function returns the keys to use in the User Info hash for the external account's display username.
# cf. http://openid.net/specs/openid-connect-core-1_0.html#UserInfoResponse
sub _POSSIBLE_DISPLAY_USERNAME_KEY_NAMES {
    return qw( email emails preferred_username name sub );
}

# This function returns the keys to use in the User Info hash for the external account's display username.
# cf. http://openid.net/specs/openid-connect-core-1_0.html#UserInfoResponse
sub _POSSIBLE_DISPLAY_USERNAME_SUBKEY_NAMES {
    return qw( preferred account business personal );
}

# This function returns the keys to use in the User Info hash for the subscriber unique identifier.
# cf. http://openid.net/specs/openid-connect-core-1_0.html#UserInfoResponse
#
#NOTE: Per the spec, everything *should* return “sub”, but
#in practice, not everything might. (TODO: List examples.)
#
sub _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES {
    return qw( sub uid );
}

# This function returns the keys used to look for the ID Token in the token response JSON hash
# cf. http://openid.net/specs/openid-connect-core-1_0.html#TokenResponse
sub _POSSIBLE_ID_TOKEN_KEY_NAMES {
    return qw( id_token );
}

# This function returns the scope to send to the provider.
# cf. http://openid.net/specs/openid-connect-core-1_0.html#ScopeClaims
sub _SCOPE { return 'openid profile email'; }

############################################################################################
# End override methods
############################################################################################

############################################################################################
# Signing key methods, these may need to be overridden in submodules
############################################################################################

# This function returns which Digest::SHA method to use for HMAC SHA signing verification.
sub _GET_HS_ALGORITHM_MAP {
    my ($self) = @_;

    # This is currently all JSON::WebToken::Crypt::HMAC (v0.10) supports as of 7/31/15
    return {
        'HS384' => 'sha384',
        'HS256' => 'sha256',
        'HS512' => 'sha512',
    };
}

# This function returns the RSA signing key assembled from the jwks_uri.
# cf. https://openid.net/specs/openid-connect-discovery-1_0.html
# cf. https://tools.ietf.org/html/draft-ietf-jose-json-web-signature-41
sub _RS_get_signing_key {
    my ( $self, $key_id, $algorithm ) = @_;

    Cpanel::LoadModule::load_perl_module('Crypt::OpenSSL::Bignum');
    Cpanel::LoadModule::load_perl_module('Crypt::OpenSSL::RSA');

    my $well_known_config = $self->get_well_known_configuration();
    my $response          = $self->_get_http_request_response( $well_known_config->{jwks_uri} );

    my $response_hr = Cpanel::JSON::Load( $response->content() );

    my ($signing_key) = grep { $_->{use} eq 'sig' && defined $key_id ? $_->{kid} eq $key_id : 1 } @{ $response_hr->{keys} };

    die Cpanel::Exception::create( 'RecordNotFound', 'The system was unable to locate the key with ID “[_1]” and the algorithm “[_2]”.', [ $key_id, $algorithm ] ) if !$signing_key;

    my $public_key_obj = $self->_get_public_key_from_signing_key_parts($signing_key);
    my $public_key_str = $public_key_obj->get_public_key_x509_string();

    return $public_key_str;
}

# This function returns the HMAC SHA signing key.
sub _HS_get_signing_key {
    my ( $self, $key_id, $algorithm ) = @_;

    Cpanel::LoadModule::load_perl_module('Digest::SHA');

    my $key_text = $self->_GET_SECRET_BASED_SIGNING_KEY_PLAINTEXT();

    my $alg_map     = $self->_GET_HS_ALGORITHM_MAP();
    my $method_name = $alg_map->{$algorithm};
    die "Unknown algorithm '$algorithm'" if !$method_name;

    my $method = Digest::SHA->can($method_name);
    die "Unknown algorithm '$algorithm'" if !$method;

    return $method->($key_text);
}

############################################################################################
# End signing key methods
############################################################################################

my $http_tiny_obj;
my $logger;

# We're using the code flow authorization authentication method (yes, I know..):
# http://openid.net/specs/openid-connect-core-1_0.html#CodeFlowAuth
sub new {
    my ( $class, %OPTS ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$OPTS{'service_name'} );

    my $self = bless {
        'service_name' => $OPTS{'service_name'},
    }, $class;

    return $self;
}

sub can_verify {
    my ($self) = @_;
    return $self->_CAN_VERIFY();
}

###########################################################################
#
# Method:
#   start_authorize
#
# Description:
#   This function gets the redirect URI to begin the authentication request from the authentication provider.
#   See: http://openid.net/specs/openid-connect-core-1_0.html#AuthRequest
#
# Parameters:
#   $state  - An arbitrary JSON-encodable scalar, arrayref, or hashref.
#             This value is sent, JSON-encoded, as the “state” parameter
#             in the request.
#             NOTE: This WILL be sent via a secure connection to the remote machine.
#
# Exceptions:
#   Cpanel::Exception::Services::NotConfigured - thrown if the provider is not configured
#   Cpanel::Exception::Services::Disabled      - thrown if the provider is not enabled on the service
#
# Returns:
#   A URI to redirect a browser to begin an authentication request.
#
sub start_authorize {
    my ( $self, $state ) = @_;

    $self->_die_if_not_configured_and_enabled();

    $self->{'client'} ||= $self->_get_client();

    my $redirect_uri = $self->_get_redirect_uri_for_current_server_port();

    return $self->{'client'}->uri_to_redirect(
        'redirect_uri' => $redirect_uri,
        'scope'        => $self->_SCOPE(),
        $state ? ( 'state' => _serialize_state($state) ) : (),
        extra => {
            access_type => q{offline},
        },
    );
}

# TODO: Document
sub _get_redirect_uri_for_current_server_port {
    my ($self) = @_;

    my $server_port = $ENV{'SERVER_PORT'} || $Cpanel::Services::Ports::SERVICE{'cpanels'};
    my $redirect_uri;

    foreach my $potential_redirect_uri ( @{ $self->_CONFIG->{redirect_uris} } ) {
        if ( $potential_redirect_uri =~ m{:\Q$server_port/} ) {
            $redirect_uri = $potential_redirect_uri;
            last;
        }
    }
    return ( $redirect_uri || $self->_CONFIG->{redirect_uris}[0] );
}

###########################################################################
#
# Method:
#   deserialize_state
#
# Description:
#   This function JSON deserializes the state sent back from the authentication request from the
#   remote server. This is the direct opposite of _serialize_state.
#
# Parameters:
#   $serialized_state - The encoded and serialized state sent back from the remote server through the authentication callback.
#
# Exceptions:
#   Cpanel::Exception::Authz::InvalidState - Thrown if there is an error decoding or deserializing the state.
#
# Returns:
#   The deserialized state sent back from the remote server in the authentication callback.
#
sub deserialize_state {
    my ( $self, $serialized_state ) = @_;

    return if !length $serialized_state;

    # Some providers like Amazon html encode the response
    if ( $serialized_state =~ m{\&\#[0-9A-Za-z]{2};} ) {
        require HTML::Entities;
        $serialized_state = HTML::Entities::decode_entities($serialized_state);
    }

    my $state;
    try {
        local $SIG{'__DIE__'};    # in case we run under cpsrvd
        $state = Cpanel::JSON::Load($serialized_state);
    }
    catch {
        _logger()->warn( 'Could not deserialize state from remote authority: ' . Cpanel::Exception::get_string($_) );
        die Cpanel::Exception::create( 'Authz::InvalidState', 'The system could not deserialize the state from remote authority.' );
    };

    return $state;
}

###########################################################################
#
# Method:
#   callback
#
# Description:
#   This function is called after receiving the authorization code from the remote server. It's used
#   to get the access token from the server using the authorization code.
#   Received response: http://openid.net/specs/openid-connect-core-1_0.html#AuthResponse
#   Access token retrieval: http://openid.net/specs/openid-connect-core-1_0.html#TokenEndpoint
#
#
# Parameters:
#   $authz_code - The authorization code sent to us by the remote server to use to retrieve
#                 an access token for the user.
#
# Exceptions:
#   Cpanel::Exception::Services::NotConfigured          - thrown if the provider is not configured
#   Cpanel::Exception::Services::Disabled               - thrown if the provider is not enabled on the service
#   Cpanel::Exception::MissingParameter                 - Thrown if the required $authz_code is missing.
#   Cpanel::Exception::Authz::AccessTokenRetrievalError - Thrown if there is an error getting the access token from the access token endpoint.
#
# Returns:
#   Returns the access token.
#
sub callback {
    my ( $self, $authz_code ) = @_;

    $self->_die_if_not_configured_and_enabled();

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'authz_code' ] ) if !length $authz_code;

    $self->{'client'} ||= $self->_get_client();

    my $access_token = $self->{'client'}->get_access_token(
        'code'         => $authz_code,
        'redirect_uri' => $self->_get_redirect_uri_for_current_server_port(),
    ) or die Cpanel::Exception::create( 'Authz::AccessTokenRetrievalError', 'The system was unable to get an access token from the remote authority at “[_1]”: “[_2]”', [ $self->start_authorize(), $self->{'client'}->errstr ] );

    return $access_token;
}

###########################################################################
#
# Method:
#   get_id_token
#
# Description:
#   This function retrieves the ID token from the access token.
#   See: http://openid.net/specs/openid-connect-core-1_0.html#CodeIDToken
#
#
# Parameters:
#   $oidc_lite_client_token_obj_or_id_token_string -  'OIDC::Lite::Client::Token' or a id_token string
#
# Exceptions:
#   Cpanel::Exception::Services::NotConfigured          - thrown if the provider is not configured
#   Cpanel::Exception::Services::Disabled               - thrown if the provider is not enabled on the service
#   Cpanel::Exception::MissingParameter - Thrown if $oidc_lite_client_token_obj_or_id_token_string is missing.
#
# Returns:
#   Returns the ID token.
#
sub get_id_token {
    my ( $self, $oidc_lite_client_token_obj_or_id_token_string ) = @_;

    $self->_die_if_not_configured_and_enabled();

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'oidc_lite_client_token_obj_or_id_token_string' ] ) if !$oidc_lite_client_token_obj_or_id_token_string;

    my $id_token_string;
    if ( ref $oidc_lite_client_token_obj_or_id_token_string ) {
        if ( try { $oidc_lite_client_token_obj_or_id_token_string->isa('OIDC::Lite::Client::Token') } ) {
            $id_token_string = $oidc_lite_client_token_obj_or_id_token_string->id_token();
        }

        if ( !length $id_token_string ) {
            for my $id_token_key ( $self->_POSSIBLE_ID_TOKEN_KEY_NAMES() ) {
                $id_token_string = $oidc_lite_client_token_obj_or_id_token_string->{$id_token_key};
                last if length $id_token_string;
            }
        }
    }
    else {
        $id_token_string = $oidc_lite_client_token_obj_or_id_token_string;
    }

    Cpanel::LoadModule::load_perl_module('OIDC::Lite::Model::IDToken');
    return OIDC::Lite::Model::IDToken->load($id_token_string);
}

###########################################################################
#
# Method:
#   get_user_info
#
# Description:
#   This function retrieves the user information from the UserInfo endpoint of the remote provider.
#   See: http://openid.net/specs/openid-connect-core-1_0.html#UserInfo
#
#
# Parameters:
#   $access_token_obj - An OIDC::Lite::Client::Token representing the access token retrieved from the code sent back in the authentication callback.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if $access_token_obj is missing.
#   Anything Cpanel::HTTP::Client can throw.
#
# Returns:
#   Returns the a hash of the user information from the UserInfo endpoint.
#
sub get_user_info {
    my ( $self, $access_token_obj ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'access_token_obj' ] ) if !$access_token_obj;

    my $config = $self->_CONFIG();

    my $response = $self->_get_http_request_response(
        $config->{user_info_uri},
        { Authorization => sprintf( 'Bearer %s', $access_token_obj->access_token ) }
    );

    my $content = $response->content();

    require Cpanel::JSON::Sanitize;
    Cpanel::JSON::Sanitize::uxxxx_to_bytes($content);

    return Cpanel::JSON::Load($content);
}

###########################################################################
#
# Method:
#   refresh_access_token
#
# Description:
#   This function renews the access token by contacting the remote authority and presenting the refresh token.
#   See: http://openid.net/specs/openid-connect-core-1_0.html#RefreshTokens
#
#
# Parameters:
#   $access_token_obj - An OIDC::Lite::Client::Token representing the access token retrieved from the code sent back in the authentication callback.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if $access_token_obj is missing.
#   Cpanel::Exception::Authz::AccessTokenRetrievalError - Thrown if there is an error getting the access token from the access token endpoint.
#
# Returns:
#   Returns a new OIDC::Lite::Client::Token.
#
sub refresh_access_token {
    my ( $self, $access_token_obj ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'access_token_obj' ] ) if !$access_token_obj;

    $self->{'client'} ||= $self->_get_client();

    my $refreshed_access_token_obj = $self->{'client'}->refresh_access_token(
        'refresh_token' => $access_token_obj->refresh_token,
      )
      or die Cpanel::Exception::create(
        'Authz::AccessTokenRetrievalError',
        'The system was unable to refresh an access token from the remote authority at “[_1]”: “[_2]”', [ $self->start_authorize(), $self->{'client'}->errstr ]
      );

    return $refreshed_access_token_obj;
}

###########################################################################
#
# Method:
#   get_documentation_url
#
# Description:
#   This function gets the documentation URL set for the module.
#
#
# Parameters:
#   None.
#
# Exceptions:
#   None.
#
# Returns:
#   Returns the documentation URL as a string.
#
sub get_documentation_url {
    my ($self) = @_;

    return $self->_DOCUMENTATION_URL();
}

###########################################################################
#
# Method:
#   get_well_known_configuration
#
# Description:
#   This function retrieves the well-known configuration from the remote authority and returns it as a hashref.
#   This function will also cache the response for 1 day after retrieving it from the remote authority.
#   cf. http://tools.ietf.org/html/rfc5785
#
#
# Parameters:
#   None.
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSON can throw or anything Cpanel::HTTP::Client can throw.
#
# Returns:
#   A hashref representing the well-known configuration for the remote authority.
#
sub get_well_known_configuration {
    my ($self) = @_;

    $self->create_storage_directories_if_missing();

    Cpanel::LoadModule::load_perl_module('Cpanel::Security::Authn::OIDCConfigCache');
    return Cpanel::Security::Authn::OIDCConfigCache->load(
        $self->get_provider_name(),
        $self->_WELL_KNOWN_CONFIG_URI(),
    );
}

###########################################################################
#
# Method:
#   clear_well_known_configuration
#
# Description:
#   This will wipe the existing cached well known configuration.
#
# Parameters:
#   None.
#
# Exceptions:
#   Any non-Cpanel::Exception::IO::UnlinkError or non ENOENT errors in Cpanel::Autodie::unlink_if_exists.
#
# Returns:
#   None.
#

sub clear_well_known_configuration {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');

    my $well_known_config_cache_path = $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR . '/.' . $self->get_provider_name() . '.well_known_config';

    Cpanel::Autodie::unlink_if_exists($well_known_config_cache_path);

    return;
}

###########################################################################
#
# Method:
#   get_client_configuration
#
# Description:
#   This returns the client configuration for the provider module as a hashref.
#
# Parameters:
#   None.
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSONReader can throw.
#
# Returns:
#   Returns the client configuration as a hashref fitting the following form, an empty hash, or undef:
# {
#     'client_id'     => The client ID obtained during setting up the authorization link with the authority server.
#     'client_secret' => The client secret obtained during setting up the authorization link with the authority server.
#     'redirect_uris' => An arrayref of URIs provided to the authority server during authorization link setup.
#                        https://tools.ietf.org/html/rfc6749#section-3.1.2
# }
#  This function returns undef if the client configuration does not exist. Or empty hash if it does exist and the current
#  user cannot read it. The current user needs to know if the provider is configured, but can only know the configuration data
#  if the user has access to read it (currently root only).
#
sub get_client_configuration {
    my ($self) = @_;

    $self->create_storage_directories_if_missing();

    my $client_config_file = $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR . '/' . $self->get_provider_name();

    if ( -r $client_config_file ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $client_config_file ) or die "Could not read configuration: $!";
        my $data               = $reader_transaction->get_data();

        # We need to set these internally because the ssl certificate may change
        $data->{redirect_uris} = $self->get_default_redirect_uris();

        return $data;
    }
    elsif ( -e _ ) {
        return {};    #exists but not readable as the current user so we need to let the user know its configured
    }

    return undef;
}

###########################################################################
#
# Method:
#   set_client_configuration
#
# Description:
#   This function sets the client configuration for the provider module.
#
# Parameters:
#   $config_hr - The configuration hashref for the provider module fitting the following form:
#                {
#                   client_id     => The client ID obtained during setting up the authorization link with the authority server.
#                   client_secret => The client secret obtained during setting up the authorization link with the authority server.
#                   redirect_uris => (optional) The URIs configured at the provider to allow for redirection. If this is not provided the system will use the SSL host for the machine or the hostname.
#                                    https://tools.ietf.org/html/rfc6749#section-3.1.2
#                }
#
# Exceptions:
#   Anything Cpanel::Transaction::File::JSON can throw.
#   Anything Cpanel::Validate::OpenIdConnect::check_hashref_or_die can throw.
#
# Returns:
#   Returns 1.
#
sub set_client_configuration {
    require Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set;
    goto \&Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set::set_client_configuration;
}

###########################################################################
#
# Method:
#   get_provider_name
#
# Description:
#   This returns the system provider name for the provider module.
#   Note: This will be lower case.
#
# Parameters:
#   None.
#
# Exceptions:
#   None.
#
# Returns:
#   Returns the lower case system provider name for the provider module as a string.
#
sub get_provider_name {
    my ($self) = @_;

    my $lc_name = $self->_PROVIDER_NAME();
    $lc_name =~ tr/A-Z/a-z/;

    return $lc_name;
}

###########################################################################
#
# Method:
#   get_provider_display_name
#
# Description:
#   This returns the display provider name for the provider module.
#
# Parameters:
#   None.
#
# Exceptions:
#   None.
#
# Returns:
#   Returns the display provider name for the provider module as a string.
#
sub get_provider_display_name {
    my ($self) = @_;

    return $self->_DISPLAY_NAME();
}

###########################################################################
#
# Method:
#   get_service_name
#
# Description:
#   This returns the service name for the provider module provided during instantiation.
#
# Parameters:
#   None.
#
# Exceptions:
#   None.
#
# Returns:
#   Returns the service name for the provider module as a string.
#
sub get_service_name {
    my ($self) = @_;
    return $self->{'service_name'};
}

###########################################################################
#
# Method:
#   get_signing_key
#
# Description:
#   This returns the signing key for signature verification.
#
# Parameters:
#   $key_id    - The ID of the key used to sign the JWT.
#   $algorithm - The algorithm used to sign the JWT.
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if key_id or algorithm are not passed.
#   Cpanel::Exception::InvalidParamter  - Thrown if the algorithm provided is unsupported by the system.
#
# Returns:
#   This returns the signing key as a string.
#
sub get_signing_key {
    my ( $self, $key_id, $algorithm ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'key_id' ] )    if !length $key_id;
    die Cpanel::Exception::create( 'MissingParameter', [ name => 'algorithm' ] ) if !length $algorithm;
    die Cpanel::Exception::create( 'InvalidParameter', 'The system does not support the algorithm “[_1]”.', [$algorithm] ) if !length $algorithm > 2;

    my $alg_type = $self->_get_alg_type($algorithm);
    die Cpanel::Exception::create( 'InvalidParameter', 'The system does not support the algorithm “[_1]”.', [$algorithm] ) if !defined $alg_type;

    my $function_name = "_${alg_type}_get_signing_key";

    if ( $self->can($function_name) ) {
        return $self->$function_name( $key_id, $algorithm );
    }

    die Cpanel::Exception::create( 'InvalidParameter', 'The system does not support the algorithm “[_1]” with type “[_2]”.', [ $algorithm, $alg_type ] );
}

###########################################################################
#
# Method:
#   get_human_readable_account_identifier_from_user_info
#
# Description:
#   This returns the display name for the external account obtained from the UserInfo payload.
#   To aid in the parsing of this hashref we've added two supporting functions for override to
#   get the possible display name key and subkey for this hash. We haven't as of yet seen a
#   hashref that has gone more than 2 levels deep, but if so this function will need to be
#   overridden in a provider module.
#
#   This always prefers the email address if we have it.
#
# Parameters:
#   $user_info_payload - The UserInfo payload for the user as a hashref. The form of this payload is generic and will
#                        change depending on provider. See description above for more info.
#                        cf. http://openid.net/specs/openid-connect-core-1_0.html#UserInfo
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if user_info_payload is not passed.
#   Cpanel::Exception::InvalidParamter  - Thrown if the human readable ID is not contained within the user_info_payload.
#                                         This means you should probably override _POSSIBLE_DISPLAY_USERNAME_KEY_NAMES for the provider.
#
# Returns:
#   This returns the human readable identifier for the external account as a string.
#
sub get_human_readable_account_identifier_from_user_info {
    my ( $self, $user_info_payload ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'user_info_payload' ] ) if !$user_info_payload;

    my @possible_keys    = $self->_POSSIBLE_DISPLAY_USERNAME_KEY_NAMES();
    my @possible_subkeys = $self->_POSSIBLE_DISPLAY_USERNAME_SUBKEY_NAMES();

    # user_info_payload may look something like this, but is dependent on the provider
    #
    #           'name'  => 'Someone'
    #           'email'  => 'someone@cpanel.net',
    #           'emails' => {
    #                        'account' => 'someone@cpanel.net',
    #                        'business' => undef,
    #                        'personal' => undef,
    #                        'preferred' => 'someone@cpanel.net'
    #                      },
    #           }

    foreach my $key (@possible_keys) {
        next if !defined $user_info_payload->{$key};
        if ( ref $user_info_payload->{$key} eq 'HASH' ) {
            foreach my $subkey (@possible_subkeys) {
                next if !defined $user_info_payload->{$key}{$subkey};
                return $user_info_payload->{$key}{$subkey};
            }
        }
        else {
            return $user_info_payload->{$key};
        }
    }

    die Cpanel::Exception::create( 'InvalidParameter', "The user information payload, “[_1]”, does not contain a known display name.", [ Cpanel::JSON::Dump($user_info_payload) ] );
}

###########################################################################
#
# Method:
#   get_display_configuration
#
# Description:
#   This returns the display configuration for the provider module.
#
# Parameters:
#   service_name - (optional) The service to get the configuration in context for.
#                  This is provided so this function may be called as a static method.
#
# Exceptions:
#   Whatever check_service_name_or_die can throw, except for the MissingParameter exception.
#
# Returns:
#   Returns the display configuration for the provider module as a hashref fitting the following form:
# {
#     label             => The text label for the button (_BUTTON_LABEL())
#     link              => The URL to use for the button (_CONFIG()->{'authorize_uri'})
#
#     color             => The button color in hex RRGGBB format (_BUTTON_COLOR())
#     textcolor         => The button text color in hex RRGGBB format (_BUTTON_TEXT_COLOR())
#
#     icon              => A base64 encoded image for the button (_BUTTON_ICON())
#     icon_type         => The MIME type of the “icon” (default: 'image/svg+xml') (_BUTTON_ICON_TYPE())
#     display_name      => The display name of the provider. 'Cpanel ID' (_DISPLAY_NAME())
#     provider_name     => The system name of the provider 'cpanelid' (_PROVIDER_NAME())
#     documentation_url => A URL to the documentation for the provider. (_DOCUMENTATION_URL())
# }
#
sub get_display_configuration {
    my ( $self, $service_name ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name ) if length $service_name;

    my $display_configs = $self->_get_custom_display_configuration( $self->get_provider_name(), $service_name );

    if ( !defined $display_configs ) {
        $display_configs = $self->_DISPLAY_CONFIG($service_name);
    }

    return $display_configs;
}

###########################################################################
#
# Method:
#   get_default_display_configuration
#
# Description:
#   This returns the default display configuration for the provider module.
#   Regardless of custom configurations made to the display configurations
#
# Parameters:
#   service_name - (optional) The service to get the configuration in context for.
#                  This is provided so this function may be called as a static method.
#
# Exceptions:
#   Whatever check_service_name_or_die can throw, except for the MissingParameter exception.
#
# Returns:
#   Returns the display configuration for the provider module as a hashref fitting the following form:
# {
#     label             => The text label for the button (_BUTTON_LABEL())
#     link              => The URL to use for the button (_CONFIG()->{'authorize_uri'})
#
#     color             => The button color in hex RRGGBB format (_BUTTON_COLOR())
#     textcolor         => The button text color in hex RRGGBB format (_BUTTON_TEXT_COLOR())
#
#     icon              => A base64 encoded image for the button (_BUTTON_ICON())
#     icon_type         => The MIME type of the “icon” (default: 'image/svg+xml') (_BUTTON_ICON_TYPE())
#     display_name      => The display name of the provider. 'Cpanel ID' (_DISPLAY_NAME())
#     provider_name     => The system name of the provider 'cpanelid' (_PROVIDER_NAME())
#     documentation_url => A URL to the documentation for the provider. (_DOCUMENTATION_URL())
# }
#

sub get_default_display_configuration {
    my ( $self, $service_name ) = @_;

    Cpanel::Validate::OpenIdConnect::check_and_normalize_service_or_die( \$service_name ) if length $service_name;

    my $display_configs = $self->_DISPLAY_CONFIG($service_name);

    return $display_configs;

}

sub _CUSTOM_DISPLAY_CONFIG_PATH {
    my ( $self, $provider_name, $service_name ) = @_;

    return sprintf(
        "%s/.%s.%s.display_configurations",
        $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR,
        $provider_name,
        $service_name,
    );
}

sub _get_custom_display_configuration {
    my ( $self, $provider_name, $service_name ) = @_;

    $self->create_storage_directories_if_missing();

    my $path = $self->_CUSTOM_DISPLAY_CONFIG_PATH( $provider_name, $service_name );

    return undef if ( !-e $path );

    my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $path );
    return $reader_transaction->get_data();

}

###########################################################################
#
# Method:
#   set_display_configuration
#
# Description:
#   This sets the display configuration settings for the provider module.
#
# Parameters:
#   service_name - (optional) The service to get the configuration in context for.
#                  This is provided so this function may be called as a static method.
#
# Exceptions:
#   Whatever check_service_name_or_die can throw, except for the MissingParameter exception.
#   Cpanel::Exception::InvalidParameter - thrown if the display configuration setting keys
#                                         are not found within the display configuration for the module.
#                                         Also thrown if the values for the keys textcolor or color are
#                                         not hexadecimal numbers without the #.
#
# Returns:
#   Returns 1.
#
sub set_display_configuration {
    require Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set;
    goto \&Cpanel::Security::Authn::Provider::OpenIdConnectBase::Set::set_display_configuration;
}

###########################################################################
#
# Method:
#   get_configuration_fields
#
# Description:
#   This returns the configuration fields required for the provider module.
#
# Parameters:
#   None.
#
# Exceptions:
#   None.
#
# Returns:
#   Returns the configuration fields required for the provider module as a hashref fitting the following form:
#   {
#       'client_id' => {
#           'description' => 'The ID of the Client',
#           'label'       => 'Client ID',
#           'value'       => $self->{client_id}
#       },
#       'client_secret' => {
#           'description' => 'The Secret of the Client',
#           'label'       => 'Client Secret',
#           'value'       => $self->{client_secret}
#       }
#   }
#
sub get_configuration_fields {
    my ($self) = @_;

    return $self->_CONFIG_FIELDS();
}

###########################################################################
#
# Method:
#   is_configured
#
# Description:
#   This returns the configuration status for the provider module.
#
# Parameters:
#   None.
#
# Exceptions:
#   Throws anything get_client_configuration can throw.
#
# Returns:
#   Returns 1 if the provider module has been configured, 0 if it has not.
#
sub is_configured {
    my ($self) = @_;

    return $self->get_client_configuration() ? 1 : 0;
}

###########################################################################
#
# Method:
#   is_enabled
#
# Description:
#   This returns the enabled status on the service (provided on instantiation) for the provider module.
#
# Parameters:
#   None.
#
# Exceptions:
#   Throws anything Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers can throw.
#
# Returns:
#   Returns 1 if the provider module has been enabled on the service, 0 if it has not.
#
sub is_enabled {
    my ($self) = @_;

    my $enabled_providers = Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_connect_providers( $self->get_service_name() );
    return 1 if $enabled_providers->{ $self->get_provider_name() } && $enabled_providers->{ $self->get_provider_name() } eq ref $self;
    return 0;
}

###########################################################################
#
# Method:
#   get_subject_unique_identifier_from_id_token
#
# Description:
#   This returns the subscriber unique identifier for the external account.
#   We've added a helper function _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES to
#   override in sub modules to facilitate the retrieval of the subscriber
#   unique id from the ID token.
#
# Parameters:
#   $id_token  - A OIDC::Lite::Model::IDToken object representing the JWT ID token provided during the authentication confirmation.
#                cf. http://openid.net/specs/openid-connect-core-1_0.html#CodeIDToken
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if id_token is not passed.
#   Cpanel::Exception::InvalidParamter  - Thrown if the subscriber unique ID is not contained within the token.
#                                         This means you should probably override _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES for the provider.
#
# Returns:
#   This returns the subscriber unique identifier for the external account as a string.
#
sub get_subject_unique_identifier_from_id_token {
    my ( $self, $id_token ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'id_token' ] ) if !$id_token;

    my @possible_keys = $self->_POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES();

    for my $key (@possible_keys) {
        next if !defined $id_token->payload()->{$key};
        return $id_token->payload()->{$key};
    }

    die Cpanel::Exception::create( 'InvalidParameter', "The [asis,ID token] payload “[_1]” does not contain a known unique identifier.", [ Cpanel::JSON::Dump( $id_token->payload() ) ] );
}

###########################################################################
#
# Method:
#   get_subject_unique_identifier_from_auth_token
#
# Description:
#   This returns the subscriber unique identifier for the external account.
#
# Parameters:
#   $third_party_auth_token  - A OIDC::Lite::Client::Token object representing the access token provided during the authentication confirmation.
#                              cf. http://openid.net/specs/openid-connect-core-1_0.html#TokenResponse
#
# Exceptions:
#   Cpanel::Exception::MissingParameter - Thrown if third_party_auth_token is not passed.
#   Cpanel::Exception::InvalidParamter  - Thrown if the subscriber unique ID is not contained within the token.
#                                         This means you should probably override _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES for the provider.
#   Anything get_id_token can throw
#
# Returns:
#   This returns the subscriber unique identifier for the external account as a string.
#
sub get_subject_unique_identifier_from_auth_token {
    my ( $self, $third_party_auth_token ) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'third_party_auth_token' ] ) if !$third_party_auth_token;

    return $self->get_subject_unique_identifier_from_id_token( $self->get_id_token($third_party_auth_token) );
}

###########################################################################
#
# Method:
#   get_default_redirect_uris
#
# Description:
#   This returns the default redirect URIs for the provider module. These redirect URIs are used
#   by the remote authentication service to validate where it is sending the client back to during
#   authentication.
#
# Parameters:
#   None.
#
# Exceptions:
#   None currently.
#
# Returns:
#   This returns an arrayref of redirect URIs.
#
sub get_default_redirect_uris {
    my ($self) = @_;

    my $provider = $self->get_provider_name();

    # Get an SSL base URI for the service to use as the base of the external authn callback URI
    # Order matters!
    # cPanel
    # WHM
    # Webmail
    return [ map { "$_/openid_connect_callback/$provider" } map { $self->_get_link_base($_) } qw( cpaneld whostmgrd webmaild ) ];
}

*_serialize_state = \&Cpanel::JSON::Dump;

sub _get_public_key_from_signing_key_parts {
    my ( $self, $key ) = @_;

    my $bignum_n = $self->_get_bignum_from_base64_string( $key->{n} );
    my $bignum_e = $self->_get_bignum_from_base64_string( $key->{e} );

    return Crypt::OpenSSL::RSA->new_key_from_parameters( $bignum_n, $bignum_e );
}

sub _get_alg_type {
    my ( $self, $algorithm ) = @_;

    $algorithm =~ s/[^A-Za-z0-9_]//g;

    my ($alg_type) = $algorithm =~ /^([A-Za-z]+)/;
    return $alg_type;
}

sub _get_client {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('OIDC::Lite::Client::WebServer');
    my $config = $self->_CONFIG();

    my $client = OIDC::Lite::Client::WebServer->new( map { $_ => $config->{$_} } qw( id secret authorize_uri access_token_uri ) );
    return $client;
}

sub _get_bignum_from_base64_string {
    my ( $self, $base64_encoded_number ) = @_;

    $base64_encoded_number = $self->_convert_from_url_base64_to_base64($base64_encoded_number);

    Cpanel::LoadModule::load_perl_module('MIME::Base64');
    my $binary_number = MIME::Base64::decode_base64($base64_encoded_number);

    return Crypt::OpenSSL::Bignum->new_from_bin($binary_number);
}

# NOTE: If we ever use this method for something that
# gives sensitive data on the query string,
# sanitize the URL before throwing any errors!
sub _get_http_request_response {
    my ( $self, $url, $headers ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::HTTP::Client');

    $http_tiny_obj ||= Cpanel::HTTP::Client->new()->die_on_http_error();

    return $http_tiny_obj->get(
        $url,
        ( ( $headers && %$headers ) ? { 'headers' => $headers } : () ),
    );
}

sub _die_if_not_configured {
    my ($self) = @_;

    if ( !$self->is_configured() ) {
        die Cpanel::Exception::create( 'Services::NotConfigured', 'The [asis,OpenID Connect] provider “[_1]” has not been configured.', [ $self->get_provider_display_name() ] );
    }

    return;
}

sub _die_if_not_enabled {
    my ($self) = @_;

    if ( !$self->is_enabled() ) {
        die Cpanel::Exception::create( 'Services::Disabled', 'The [asis,OpenID Connect] provider “[_1]” is disabled on the service “[_2]”.', [ $self->get_provider_display_name(), $self->get_service_name() ] );
    }

    return;
}

sub _die_if_not_configured_and_enabled {
    my ($self) = @_;

    $self->_die_if_not_configured();
    $self->_die_if_not_enabled();

    return;
}

sub _convert_from_url_base64_to_base64 {
    my ( $self, $base64_encoded_entity ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Base64');

    $base64_encoded_entity = Cpanel::Base64::from_url($base64_encoded_entity);

    $base64_encoded_entity =~ tr|A-Za-z0-9+=/||cd;

    return Cpanel::Base64::pad($base64_encoded_entity);
}

sub _set_provider_client_configuration {
    my ( $class, $client_config ) = @_;

    $class->create_storage_directories_if_missing();

    Cpanel::LoadModule::load_perl_module('Cpanel::Transaction::File::JSON');
    my $transaction = Cpanel::Transaction::File::JSON->new(
        path        => $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR . '/' . $class->get_provider_name(),
        permissions => $Cpanel::Security::Authn::Config::CLIENT_CONFIG_FILE_PERMS,
    );

    $transaction->set_data($client_config);

    return $transaction->save_and_close_or_die();
}

sub create_storage_directories_if_missing {
    return if $> != 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

    my $perms = $Cpanel::Security::Authn::Config::CLIENT_CONFIG_DIR_PERMS;

    my @dir_vars = qw(
      AUTHENTICATION_CLIENT_CONFIG_DIR
      OPEN_ID_CLIENT_CONFIG_DIR
    );

    for my $dir (@dir_vars) {
        $dir = ${ *{ $Cpanel::Security::Authn::Config::{$dir} }{'SCALAR'} };

        Cpanel::Mkdir::ensure_directory_existence_and_mode(
            $dir,
            $perms,
        );
    }

    return;
}

# DO NOT USE THIS FUNCTION IN NEW CODE AS PPI DOES NOT KNOW HOW TO GROK IT
sub _load_modules {
    my (@modules) = @_;

    #Allow this method to be called statically or dynamically.
    if ( try { $modules[0]->isa(__PACKAGE__) } ) {
        shift @modules;
    }

    for my $module (@modules) {
        Cpanel::LoadModule::load_perl_module($module);
    }
    return;
}

# This function is used to find the best SSL domain and port for the target cPanel service (such as cpaneld, whostmgrd, or webmaild).
# The URI obtained from this function is used to craft links to the service for external authentication
sub _get_link_base {
    my ( $self, $service_name ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Services::Uri');

    return scalar Cpanel::Services::Uri::get_service_ssl_base_uri_by_service_name( $service_name || $self->get_service_name() );
}

sub _logger {

    Cpanel::LoadModule::load_perl_module('Cpanel::Logger');
    return $logger ||= Cpanel::Logger->new();
}

1;
