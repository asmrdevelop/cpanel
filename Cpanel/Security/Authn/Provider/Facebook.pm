package Cpanel::Security::Authn::Provider::Facebook;

# cpanel - Cpanel/Security/Authn/Provider/Facebook.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#NOTE: Facebook does not implement OpenID Connect as of October 2015.
#This module interacts with their OAuth2 implementation.

#####################################################################################
# This module is provided AS-IS with no warranty and with no intention of support.
# The intent is to provide a starting point for developing your own OpenID
# Connect provider module. We strongly recommend that you evaluate the module
# for your company's own security requirements.
#####################################################################################

use strict;

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

my $image = <<SVG;
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxNTYuODkx
IiBoZWlnaHQ9IjMwMi4xMSIgdmlld0JveD0iMCAwIDExNy42Njc5NyAyMjYuNTgyMjEiPjxw
YXRoIGQ9Ik0zNC43OCAyMjYuNTgyVjEyMy4yM0gwVjgyLjk1aDM0Ljc4VjUzLjI0QzM0Ljc4
IDE4Ljc3IDU1LjgzNyAwIDg2LjU4NyAwYzE0LjczIDAgMjcuMzkgMS4wOTggMzEuMDgyIDEu
NTg2djM2LjAyN2wtMjEuMzI4LjAwOGMtMTYuNzI3IDAtMTkuOTY1IDcuOTUtMTkuOTY1IDE5
LjYxdjI1LjcyaDM5Ljg4N2wtNS4xOTIgNDAuMjhINzYuMzc1djEwMy4zNTIiIGZpbGw9IiNm
ZmYiLz48L3N2Zz4=
SVG

sub _SCOPE             { return 'public_profile email'; }
sub _DISPLAY_NAME      { return 'Facebook'; }
sub _PROVIDER_NAME     { return 'facebook'; }
sub _DOCUMENTATION_URL { return 'https://developers.facebook.com/docs/facebook-login/'; }

sub _BASE_URI { return 'https://graph.facebook.com' }

sub _BUTTON_COLOR      { return '3B5998'; }
sub _BUTTON_TEXT_COLOR { return 'FFFFFF'; }

sub _BUTTON_ICON { return $image; }

# IMPORTANT: Since Facebook only supports OAuth instead of OpenID Connect verification of ID Tokens cannot be done!
# See: http://openid.net/specs/openid-connect-core-1_0.html#CodeIDToken
sub _CAN_VERIFY { return 0; }

sub _CONFIG {
    my ($self) = @_;
    my $base_uri = $self->_BASE_URI();

    return {
        %{ $self->SUPER::_CONFIG() },
        'authorize_uri'    => 'https://www.facebook.com/dialog/oauth',
        'access_token_uri' => $base_uri . '/oauth/access_token',
        'user_info_uri'    => $base_uri . '/me',
    };
}

# This function returns the required configuration fields for the provider module. This should be overridden if your provider requires different information.
sub _CONFIG_FIELDS {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return {
        'client_id' => {
            'label'         => 'App ID',
            'description'   => 'The ID of the Facebook Application',
            'value'         => $client_config->{client_id},
            'display_order' => 0,
        },
        'client_secret' => {
            'label'         => 'App Secret',
            'description'   => 'The Secret of the Facebook Application',
            'value'         => $client_config->{client_secret},
            'display_order' => 1,
        },
    };
}

# Facebook technically isn't openid connect so they didn't implement one it appears
sub get_well_known_configuration {
    return {};
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
#   $id_token_string -  'OIDC::Lite::Client::Token' or a id_token string
#
# Exceptions:
#   None that I know of yet.
#
# Returns:
#   Returns the ID token.
#
sub get_id_token {
    my ( $self, $oidc_lite_client_token_obj_or_id_token_string ) = @_;

    if ( ref $oidc_lite_client_token_obj_or_id_token_string ) {
        $self->_load_modules(qw( OIDC::Lite::Model::IDToken ));
        my $decoded  = $self->get_user_info($oidc_lite_client_token_obj_or_id_token_string);
        my $id_token = OIDC::Lite::Model::IDToken->new(
            'header' => {
                'kid' => '1',
                'alg' => 'none',
                'typ' => 'JWT'
            },
            'payload' => { 'sub' => $decoded->{'id'}, 'name' => $decoded->{'name'}, 'picture' => $decoded->{'picture'} },
            'key'     => undef,
        );
        $id_token->get_token_string();    # ensure we create the string
        return $id_token;
    }

    return $self->SUPER::get_id_token($oidc_lite_client_token_obj_or_id_token_string);
}

sub get_user_info {
    my ( $self, $access_token_obj ) = @_;

    my $user_info = $self->SUPER::get_user_info($access_token_obj);

    return undef if !$user_info;

    $user_info->{'picture'} = _BASE_URI() . "/$user_info->{'id'}/picture?type=square";
    return $user_info;
}

1;
