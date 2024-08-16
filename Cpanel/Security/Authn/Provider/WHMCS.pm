package Cpanel::Security::Authn::Provider::WHMCS;

# cpanel - Cpanel/Security/Authn/Provider/WHMCS.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#####################################################################################
# This module is provided AS-IS with no warranty and with no intention of support.
# The intent is to provide a starting point for developing your own OpenID
# Connect provider module. We strongly recommend that you evaluate the module
# for your company's own security requirements.
#####################################################################################

use strict;

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

use Cpanel::JSON       ();
use Cpanel::LoadModule ();
use Cpanel::Exception  ();

my $image = <<SVG;
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0
NzEuNzk5OTkgNDc0LjEwMDAxIiBpZD0ic3ZnMiIgd2lkdGg9IjQ3MS44IiBoZWlnaHQ9IjQ3
NC4xIj48c3R5bGUgaWQ9InN0eWxlNCI+LnN0MHtkaXNwbGF5Om5vbmV9LnN0MXtmaWxsOiM3
M2NiMGJ9LnN0MntmaWxsOiNkOWQ5ZDl9PC9zdHlsZT48ZyBpZD0iTGF5ZXJfMiI+PGcgaWQ9
Imc5Ij48cGF0aCBjbGFzcz0ic3QxIiBkPSJNNDcxLjMgMjYwLjJ2LTQybC01Ni40LTE3LjYt
NC4zLTIwLjcgMzkuOS00MS0yMC43LTM4LjMtNTcuNCAxNC45LTE0LjQtMTQuOSAxNC45LTU1
LjktMzcuOC0yMi45LTQyIDQxLjUtMjEuMy02LjRMMjU4IC42aC00NC43TDIwMS4xIDU3bC0y
My45IDYuNC0zOC44LTQxLjUtMzguMyAyMS44IDE2IDU0LjgtMTYgMTYuNS01Ni40LTE0Ljkt
MjEuOCAzNy44IDQxIDQxLjUtNiAyMC43TC41IDIxNS41IDAgMjU4LjZsNTYuOSAxNC45IDQu
OCAyMy45LTM5LjkgMzkuNCAyMC43IDM2LjcgNTguNS0xNC45IDE0LjQgMTctMTYgNTMuMiAz
OS40IDIyLjkgMzguMy00MC40IDIyLjkgNS45IDEzLjMgNTYuNCA0NC43LjUgMTMuMy01Ni45
IDIyLjktNi45IDQxIDQyLjYgNDAuNC0yMy45LTE3LjYtNTUuMyAxNS40LTE2IDU2LjkgMTcu
NiAyMC4yLTM5LjktNDEtMzcuMiA0LjMtMjMuOSA1Ny41LTE0LjF6TTIzNS42IDM0OGMtNjEu
NSAwLTExMS4zLTQ5LjktMTExLjMtMTExLjMgMC02MS41IDQ5LjktMTExLjMgMTExLjMtMTEx
LjNzMTExLjMgNDkuOCAxMTEuMyAxMTEuMmMwIDYxLjUtNDkuOCAxMTEuNC0xMTEuMyAxMTEu
NHoiIGlkPSJwYXRoMTEiIGZpbGw9IiM3M2NiMGIiLz48cGF0aCBjbGFzcz0ic3QyIiBkPSJN
NDcxLjggMTM4LjF2LTIyLjRsLTMwLTkuMy0yLjMtMTEgMjEuMi0yMS44LTExLTIwLjQtMzAu
NiA3LjktNy42LTcuOSA3LjktMjkuNy0yMC4xLTEyLjItMjIuNCAyMi4xLTExLjMtMy40LTcu
NC0zMGgtMjMuOGwtNi41IDMwLTEyLjcgMy40LTIwLjctMjIuMS0yMC40IDExLjYgOC41IDI5
LjItOC41IDguOC0zMC03LjktMTEuNiAyMC4xIDIxLjggMjIuMS0zLjEgMTEtMzAgOC4yLS4z
IDIyLjkgMzAuMyA3LjkgMi41IDEyLjctMjEuMiAyMSAxMSAxOS41IDMxLjItNy45IDcuNiA5
LjEtOC41IDI4LjMgMjEgMTIuMiAyMC40LTIxLjUgMTIuMiAzLjEgNy4xIDMwIDIzLjguMyA3
LjEtMzAuMyAxMi4yLTMuNyAyMS44IDIyLjcgMjEuNS0xMi43LTkuMy0yOS41IDguMi04LjUg
MzAuMyA5LjMgMTAuOC0yMS4yLTIyLTE5LjggMi4zLTEyLjcgMzAuNi03LjV6bS0xMjUuNSA0
Ny42Yy0zMyAwLTU5LjgtMjYuOC01OS44LTU5LjhzMjYuOC01OS44IDU5LjgtNTkuOCA1OS44
IDI2LjggNTkuOCA1OS44YzAgMzMuMS0yNi44IDU5LjgtNTkuOCA1OS44eiIgaWQ9InBhdGgx
MyIgZmlsbD0iI2Q5ZDlkOSIvPjwvZz48L2c+PC9zdmc+
SVG

sub _DISPLAY_NAME      { return 'WHMCS'; }
sub _PROVIDER_NAME     { return 'whmcs'; }
sub _DOCUMENTATION_URL { return 'http://docs.whmcs.com/WHMCS_OpenID_and_cPanel_Setup_Guide'; }

sub _BUTTON_COLOR      { return '00455e'; }
sub _BUTTON_TEXT_COLOR { return 'FFFFFF'; }

sub _BUTTON_ICON      { return $image; }
sub _BUTTON_ICON_TYPE { return 'image/svg+xml'; }

sub _CAN_VERIFY { return 0; }

sub _WELL_KNOWN_CONFIG_URI {
    my ($self) = @_;
    return $self->get_client_configuration()->{'well_known_config_uri'};
}

sub _CONFIG_FIELDS {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return {
        %{ $self->SUPER::_CONFIG_FIELDS() },
        'well_known_config_uri' => {
            'label'         => 'Well Known Config URI',
            'description'   => 'The URI to the well known configuration for the Open ID Connect Provider',
            'value'         => $client_config->{well_known_config_uri},
            'display_order' => 2,
        },
    };
}

my $http_tiny_obj;
###########################################################################
#
# Description:
#   This function retrieves the user information from the UserInfo endpoint of the remote provider.
#   See: http://openid.net/specs/openid-connect-core-1_0.html#UserInfo
#
#   Due to issue an issue with common PHP/Apache configurations, the 'Authorization' header used in the
#   base class is not a reliable.  This is compounded by the fact that mod_rewrite is not ubiquitous to
#   WHMCS environments. The token could be passed as a GET parameter, but that might get exposed in logs.
#   The least problematic solution is POST with data access_token=$token (though this does require the
#   WHMCS websever to support CONTENT_TYPE; application/x-www-form-urlencoded MUST be valided in the
#   request)
#   See: http://tools.ietf.org/html/rfc6750#section-2.2
#   See: http://php.net/manual/en/features.http-auth.php  (hunt for 'Authorization' for several user comments)
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

    my $response = $self->_post_http_request_response(
        $config->{user_info_uri},
        { access_token => $access_token_obj->access_token }
    );

    my $content = $response->content();

    require Cpanel::JSON::Sanitize;
    Cpanel::JSON::Sanitize::uxxxx_to_bytes($content);

    return Cpanel::JSON::Load($content);
}

###########################################################################

#overridden in tests
sub _post_http_request_response {
    my ( $self, $url, $postdata ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::HTTP::Client');

    $http_tiny_obj ||= Cpanel::HTTP::Client->new()->die_on_http_error();

    return $http_tiny_obj->post_form(
        $url,
        ( ( $postdata && %$postdata ) ? ($postdata) : () )
    );
}

1;
