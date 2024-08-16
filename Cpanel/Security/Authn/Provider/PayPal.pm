package Cpanel::Security::Authn::Provider::PayPal;

# cpanel - Cpanel/Security/Authn/Provider/PayPal.pm
#                                                  Copyright 2022 cPanel, L.L.C.
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
use warnings;

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

sub _BUTTON_ICON {

    #This icon was retrieved from http://paypal.com on 21 Jan 2016.
    #https://www.paypalobjects.com/webstatic/i/logo/rebrand/ppcom.svg
    return <<SVG;
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyNS41NzYi
IGhlaWdodD0iMzAuMTc3IiB2aWV3Qm94PSIwIDAgMjUuNTc2MzUzIDMwLjE3NyI+PHBhdGgg
ZD0iTTcuMjY2IDI5LjE1NGwuNTIzLTMuMzIyLTEuMTY2LS4wMjdIMS4wNkw0LjkyOCAxLjI5
MmEuMzE2LjMxNiAwIDAgMSAuMzE0LS4yNjhoOS4zOGMzLjExNSAwIDUuMjY0LjY0OCA2LjM4
NiAxLjkyNy41MjYuNi44NiAxLjIyOCAxLjAyMyAxLjkxOC4xNy43MjQuMTcyIDEuNTkuMDA2
IDIuNjQ0bC0uMDEyLjA3N3YuNjc1bC41MjYuMjk4YTMuNjkgMy42OSAwIDAgMSAxLjA2NS44
MTJjLjQ1LjUxMy43NCAxLjE2NS44NjQgMS45MzguMTI2Ljc5NS4wODQgMS43NC0uMTI0IDIu
ODEyLS4yNCAxLjIzMi0uNjI4IDIuMzA1LTEuMTUyIDMuMTgzYTYuNTQ3IDYuNTQ3IDAgMCAx
LTEuODI1IDJjLS42OTcuNDk0LTEuNTI0Ljg3LTIuNDYgMS4xMS0uOTA1LjIzNS0xLjkzOC4z
NTQtMy4wNy4zNTRoLS43M2MtLjUyMyAwLTEuMDMuMTg4LTEuNDI4LjUyNWEyLjIxIDIuMjEg
MCAwIDAtLjc0NCAxLjMyOGwtLjA1NS4zLS45MjQgNS44NTQtLjA0My4yMTRjLS4wMS4wNjgt
LjAzLjEwMi0uMDU4LjEyNWEuMTU1LjE1NSAwIDAgMS0uMDk3LjAzNEg3LjI2NnoiIGZpbGw9
IiMyNTNiODAiLz48cGF0aCBkPSJNMjMuMDQ4IDcuNjY3Yy0uMDI4LjE4LS4wNi4zNjItLjA5
Ni41NS0xLjIzNyA2LjM1LTUuNDcgOC41NDUtMTAuODc0IDguNTQ1SDkuMzI2Yy0uNjYgMC0x
LjIxOC40OC0xLjMyIDEuMTMybC0xLjQxIDguOTM2LS40IDIuNTMzYS43MDQuNzA0IDAgMCAw
IC42OTYuODE0aDQuODhjLjU4IDAgMS4wNy0uNDIgMS4xNi0uOTlsLjA1LS4yNDguOTE4LTUu
ODMzLjA2LS4zMmMuMDktLjU3Mi41OC0uOTkyIDEuMTYtLjk5MmguNzNjNC43MjggMCA4LjQz
LTEuOTIgOS41MTItNy40NzYuNDUyLTIuMzIyLjIxOC00LjI2LS45NzgtNS42MjNhNC42Njcg
NC42NjcgMCAwIDAtMS4zMzYtMS4wM3oiIGZpbGw9IiMxNzliZDciLz48cGF0aCBkPSJNMjEu
NzU0IDcuMTVhOS43NTcgOS43NTcgMCAwIDAtMS4yMDMtLjI2NiAxNS4yODQgMTUuMjg0IDAg
MCAwLTIuNDI1LS4xNzdoLTcuMzUyYTEuMTcyIDEuMTcyIDAgMCAwLTEuMTYuOTkyTDguMDUg
MTcuNjA1bC0uMDQ1LjI5YTEuMzM2IDEuMzM2IDAgMCAxIDEuMzItMS4xMzNoMi43NTNjNS40
MDUgMCA5LjYzNy0yLjE5NSAxMC44NzQtOC41NDUuMDM3LS4xODguMDY4LS4zNy4wOTYtLjU1
YTYuNTk0IDYuNTk0IDAgMCAwLTEuMDE3LS40M2MtLjA5LS4wMy0uMTgyLS4wNTgtLjI3Ni0u
MDg2eiIgZmlsbD0iIzIyMmQ2NSIvPjxwYXRoIGQ9Ik05LjYxNCA3LjdhMS4xNyAxLjE3IDAg
MCAxIDEuMTYtLjk5Mmg3LjM1Yy44NzIgMCAxLjY4NS4wNTcgMi40MjcuMTc3YTkuNzU3IDku
NzU3IDAgMCAxIDEuNDguMzUzYy4zNjcuMTIuNzA2LjI2NCAxLjAyLjQzLjM2Ny0yLjM0OC0u
MDA0LTMuOTQ2LTEuMjczLTUuMzkzQzIwLjM3Ny42ODIgMTcuODUzIDAgMTQuNjIyIDBoLTku
MzhjLS42NiAwLTEuMjIzLjQ4LTEuMzI1IDEuMTMzTC4wMSAyNS44OThjLS4wNzcuNDkuMy45
MzIuNzk1LjkzMmg1Ljc5bDEuNDU1LTkuMjI1TDkuNjE0IDcuN3oiIGZpbGw9IiMyNTNiODAi
Lz48L3N2Zz4=
SVG
}

sub _DISPLAY_NAME  { return 'PayPal'; }
sub _PROVIDER_NAME { return 'paypal'; }

sub _BUTTON_COLOR      { return 'ffffff'; }
sub _BUTTON_TEXT_COLOR { return '000000'; }

#http://stackoverflow.com/questions/31143353/using-login-with-paypal-and-using-openid-with-aws-cognito
sub _WELL_KNOWN_CONFIG_URI {
    return 'https://www.paypalobjects.com/.well-known/openid-configuration';
}

sub _DOCUMENTATION_URL {
    return 'https://go.cpanel.net/paypaldocs';
}

sub _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES {
    my ($self) = @_;
    return ( $self->SUPER::_POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES(), 'aud' );
}

#----------------------------------------------------------------------
#This is what will work with the documented API as of 21 Jan 2016:
#
#sub _CAN_VERIFY { return 0; }
#
#sub _WELL_KNOWN_CONFIG_URI {
#    return 'https://www.paypalobjects.com/.well-known/openid-configuration';
#}
#sub _CONFIG {
#    my ($self) = @_;
#    my $base_uri = 'https://api.paypal.com/v1/identity/openidconnect';
#
#    return {
#        %{ $self->SUPER::_CONFIG() },
#        'authorize_uri'    => 'https://www.paypal.com/webapps/auth/protocol/openidconnect/v1/authorize',
#        'access_token_uri' => "$base_uri/tokenservice",
#        'user_info_uri'    => "$base_uri/userinfo/?schema=openid",
#    };
#}
#
#sub _POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES {
#    my ($self) = @_;
#    return( $self->SUPER::_POSSIBLE_UNIQUE_IDENTIFIER_KEY_NAMES(), 'aud' );
#}
#
#sub get_well_known_configuration {
#    return {};
#}
#----------------------------------------------------------------------

1;
