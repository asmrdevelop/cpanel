package Cpanel::Security::Authn::Provider::Amazon;

# cpanel - Cpanel/Security/Authn/Provider/Amazon.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#NOTE: Amazon does not implement OpenID Connect as of October 2015.
#This module interacts with their OAuth2 implementation.

#####################################################################################
# This module is provided AS-IS with no warranty and with no intention of support.
# The intent is to provide a starting point for developing your own OpenID
# Connect provider module. We strongly recommend that you evaluate the module
# for your company's own security requirements.
#####################################################################################

use strict;

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

my $image = <<EOF;
iVBORw0KGgoAAAANSUhEUgAAACMAAAAjCAIAAACRuyQOAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyRpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMy1jMDExIDY2LjE0NTY2MSwgMjAxMi8wMi8wNi0xNDo1NjoyNyAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNiAoTWFjaW50b3NoKSIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo2MEFENjJENTdBQTAxMUU1OEUzNEUzNjExNTNDRTVCQiIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo2MEFENjJENjdBQTAxMUU1OEUzNEUzNjExNTNDRTVCQiI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOjYwQUQ2MkQzN0FBMDExRTU4RTM0RTM2MTE1M0NFNUJCIiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjYwQUQ2MkQ0N0FBMDExRTU4RTM0RTM2MTE1M0NFNUJCIi8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+IRfu3gAABDVJREFUeNrsl3tsU1Ucx8+5796+troVByugc5Y3Y0yYGVQUhQk60agMgiMsIzMEwcRHBn+IoAaM0RD/IAYjf2CYgol0Dpe5sRhRphASGxljlA0Yy9yz7dr1cd/H23VpC5tLwx2Lf3jSP3pOvrmf/s79nu/vlMhZ7ABTMjAwVWOUhGHwPkIQSpAUBd1HEoRTuntEijqzUV/8tGPF48tm2mbgOO4PBC5fueqsbWhrv5VqYal4b/trr1RWlKWZTXetD/kDv1+49Ma7+1Mh4ZYHZ02s2Fq6YUflthimt2/AN+T3eH3paWZ1yjB0ZsYDAs+5Wtq01pRuNjb+UB2vpnJXVWvbtXCEr//+eGZmRryyx1aVIIQ0nacnVy6PYz78+PDZX5p7+r1qTavWlwZDodi6KqApUqsjzp2/uPOtvUa9obxs4/GTTjjiV4KkeEH0+QIGvT4mI0mC4wVNpEFfoL7pvPql+rsaFQCx0T0wsAyr18Vlj8zO/rPFPTkuz8qatqJwaUF+3lx7bs7DURPFC4oefFnRfp7U9wxPfPmZ/dHcsS6/U6aVBP9ochIEHsMIvFD7Y93nR7/GMKz+9AmapmIiSZa1kja/vD6OUc2WV7RO5DlFkWidAYOJUOZ5Titp947t8U17Z88+PhJUGaN+S3K2KEqa+pPqaTXi4lN3+w0Mjz5d5bEMlaxkWZ0mkp6hkl1QWb5FkQSBC1O0zll9NFl5aP8eTbknSHJF2UaSHN2l+fPmEhB5vEPHjnwyZ449WWm1WjtvdlzruH3vaXTg4KfJ0107X288c2rRwgVqyjlrajkuYYSu7h5NWd7qvlGweJ7Nln3X+tqSV0/WNHZ13ixes1qd5hetudU9ME4dSIJARjD6sqGjcEl3mAUQn4CXMzPr+eKn1E4x6PVevOS64Er0iBeffaLh5+YQJ95hJSS/7/CX5lO4mQQmDHDiwW85WLh8Wc02UHV6+Fxv5mQ1cgbyD6WJ7QHDFy95+3zyhjxdH4LYAMc4jmCHNlua90ZemNU3KSQO0Vd9Bgvu50N8R2/wbw//62Ux0QlX20IfvG2y6sLuBt+bPzHXA0Y04Zb+29DBSMWCoU3PmQGrLzkQGhTZ5n38Mx/BREY0dembdsvlC8WKLdPqNgHQEfK0Rr75S/ntNtHuo4clWo6Kx1wLkUJC0ULz8zOErYukoqW6/ukmMDz98FfBU241dtncdD/nY0ISNV53R8rK7PB7awm9nbLaEOBl4B/5BGQuIg/zSFDdBIGOgGYGwww4sOAggwR6sr8TBq7wVWck12CioZQvCVa7CA4xE90jWIwrmCGvs0NHLgZMuDULAGrkBMayVW1JPOrvgbxHqmtVzl5HLQOkCKhx+06qt7BongLBSMoGGrEkUm/WggzCAgwIWFjCFUim8oRUe676Y70i8IpjY/g/+1/jf9I9jX8EGABAaKKdbFlAwQAAAABJRU5ErkJggg==
EOF

sub _SCOPE             { return 'profile'; }
sub _DISPLAY_NAME      { return 'Amazon'; }
sub _PROVIDER_NAME     { return 'Amazon'; }
sub _DOCUMENTATION_URL { return 'https://login.amazon.com/documentation' }

sub _BASE_URI { return 'https://api.amazon.com' }

sub _BUTTON_COLOR      { return '232f3e'; }
sub _BUTTON_TEXT_COLOR { return 'FFFFFF'; }

sub _BUTTON_ICON      { return $image; }
sub _BUTTON_ICON_TYPE { return 'image/png' }

# IMPORTANT: Since Amazon only supports OAuth instead of OpenID Connect verification of ID Tokens cannot be done!
# See: http://openid.net/specs/openid-connect-core-1_0.html#CodeIDToken
sub _CAN_VERIFY { return 0; }

sub _CONFIG {
    my ($self) = @_;
    my $base_uri = $self->_BASE_URI();

    return {
        %{ $self->SUPER::_CONFIG() },
        'authorize_uri'    => 'https://www.amazon.com/ap/oa',
        'access_token_uri' => $base_uri . '/auth/O2/token',
        'user_info_uri'    => $base_uri . '/user/profile',
    };
}

# This function returns the required configuration fields for the provider module. This should be overridden if your provider requires different information.
sub _CONFIG_FIELDS {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return {
        'client_id' => {
            'label'         => 'App ID',
            'description'   => 'The ID of the Amazon Application',
            'value'         => $client_config->{client_id},
            'display_order' => 0,
        },
        'client_secret' => {
            'label'         => 'App Secret',
            'description'   => 'The Secret of the Amazon Application',
            'value'         => $client_config->{client_secret},
            'display_order' => 1,
        },
    };
}

# Amazon technically isn't openid connect so they didn't implement one it appears
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
            'payload' => { 'user_id' => $decoded->{'user_id'}, 'sub' => $decoded->{'email'}, 'name' => $decoded->{'name'}, 'email' => $decoded->{'email'} },
            'key'     => undef,
        );
        $id_token->get_token_string();    # ensure we create the string
        return $id_token;
    }

    return $self->SUPER::get_id_token($oidc_lite_client_token_obj_or_id_token_string);
}

1;
