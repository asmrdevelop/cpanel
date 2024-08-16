package Cpanel::Security::Authn::Provider::Slack;

# cpanel - Cpanel/Security/Authn/Provider/Slack.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Security::Authn::Provider::Slack

=head1 SYNOPSIS

N/A

=head1 DESCRIPTION

A Slack external authentication module.

See cPanel’s documentation on external authentication modules
for more details.

=head2 METHODS

=cut

use strict;
use warnings;

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

use constant _BUTTON_ICON => <<END;
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIGlkPSJMYXllcl8xIiB2
aWV3Qm94PSIwIDAgMTIxLjk0MTU0IDEyMS44NDE1NCIgd2lkdGg9IjEyMS45NDIiIGhlaWdo
dD0iMTIxLjg0MiI+PHN0eWxlIGlkPSJzdHlsZTc3Ij4uc3Qwe2ZpbGw6I2VjYjMyZH0uc3Qx
e2ZpbGw6IzYzYzFhMH0uc3Qye2ZpbGw6I2UwMWE1OX0uc3Qze2ZpbGw6IzMzMTQzM30uc3Q0
e2ZpbGw6I2Q2MjAyN30uc3Q1e2ZpbGw6Izg5ZDNkZn0uc3Q2e2ZpbGw6IzI1OGI3NH0uc3Q3
e2ZpbGw6IzgxOWMzY308L3N0eWxlPjxnIGlkPSJnOTciPjxnIGlkPSJnOTUiPjxwYXRoIGNs
YXNzPSJzdDAiIGQ9Ik03OS4wMyA3LjUxYy0xLjktNS43LTgtOC44LTEzLjctNy01LjcgMS45
LTguOCA4LTcgMTMuN2wyOC4xIDg2LjRjMS45IDUuMyA3LjcgOC4zIDEzLjIgNi43IDUuOC0x
LjcgOS4zLTcuOCA3LjQtMTMuNCAwLS4yLTI4LTg2LjQtMjgtODYuNHoiIGlkPSJwYXRoNzki
IGZpbGw9IiNlY2IzMmQiLz48cGF0aCBjbGFzcz0ic3QxIiBkPSJNMzUuNTMgMjEuNjFjLTEu
OS01LjctOC04LjgtMTMuNy03LTUuNyAxLjktOC44IDgtNyAxMy43bDI4LjEgODYuNGMxLjkg
NS4zIDcuNyA4LjMgMTMuMiA2LjcgNS44LTEuNyA5LjMtNy44IDcuNC0xMy40IDAtLjItMjgt
ODYuNC0yOC04Ni40eiIgaWQ9InBhdGg4MSIgZmlsbD0iIzYzYzFhMCIvPjxwYXRoIGNsYXNz
PSJzdDIiIGQ9Ik0xMTQuNDMgNzkuMDFjNS43LTEuOSA4LjgtOCA3LTEzLjctMS45LTUuNy04
LTguOC0xMy43LTdsLTg2LjUgMjguMmMtNS4zIDEuOS04LjMgNy43LTYuNyAxMy4yIDEuNyA1
LjggNy44IDkuMyAxMy40IDcuNC4yIDAgODYuNS0yOC4xIDg2LjUtMjguMXoiIGlkPSJwYXRo
ODMiIGZpbGw9IiNlMDFhNTkiLz48cGF0aCBjbGFzcz0ic3QzIiBkPSJNMzkuMjMgMTAzLjUx
YzUuNi0xLjggMTIuOS00LjIgMjAuNy02LjctMS44LTUuNi00LjItMTIuOS02LjctMjAuN2wt
MjAuNyA2Ljd6IiBpZD0icGF0aDg1IiBmaWxsPSIjMzMxNDMzIi8+PHBhdGggY2xhc3M9InN0
NCIgZD0iTTgyLjgzIDg5LjMxYzcuOC0yLjUgMTUuMS00LjkgMjAuNy02LjctMS44LTUuNi00
LjItMTIuOS02LjctMjAuN2wtMjAuNyA2Ljd6IiBpZD0icGF0aDg3IiBmaWxsPSIjZDYyMDI3
Ii8+PHBhdGggY2xhc3M9InN0NSIgZD0iTTEwMC4yMyAzNS41MWM1LjctMS45IDguOC04IDct
MTMuNy0xLjktNS43LTgtOC44LTEzLjctN2wtODYuNCAyOC4xYy01LjMgMS45LTguMyA3Ljct
Ni43IDEzLjIgMS43IDUuOCA3LjggOS4zIDEzLjQgNy40LjIgMCA4Ni40LTI4IDg2LjQtMjh6
IiBpZD0icGF0aDg5IiBmaWxsPSIjODlkM2RmIi8+PHBhdGggY2xhc3M9InN0NiIgZD0iTTI1
LjEzIDU5LjkxYzUuNi0xLjggMTIuOS00LjIgMjAuNy02LjctMi41LTcuOC00LjktMTUuMS02
LjctMjAuN2wtMjAuNyA2Ljd6IiBpZD0icGF0aDkxIiBmaWxsPSIjMjU4Yjc0Ii8+PHBhdGgg
Y2xhc3M9InN0NyIgZD0iTTY4LjYzIDQ1LjgxYzcuOC0yLjUgMTUuMS00LjkgMjAuNy02Ljct
Mi41LTcuOC00LjktMTUuMS02LjctMjAuN2wtMjAuNyA2Ljd6IiBpZD0icGF0aDkzIiBmaWxs
PSIjODE5YzNjIi8+PC9nPjwvZz48L3N2Zz4K
END

use constant {
    _DISPLAY_NAME  => 'Slack',
    _PROVIDER_NAME => 'slack',

    _BUTTON_COLOR      => 'ffffff',
    _BUTTON_TEXT_COLOR => '000000',

    _DOCUMENTATION_URL => 'https://api.slack.com/apps',

    _CAN_VERIFY => 0,

    _SCOPE => 'identity.basic identity.email identity.avatar',

    BASE_URI => 'https://slack.com/',
};

=head2 get_well_known_configuration()

This returns an empty hash reference.

=cut

# Slack technically isn't openid connect so they didn't implement one it appears
sub get_well_known_configuration {
    return {};
}

sub _CONFIG {
    my ($self) = @_;
    my $base_uri = $self->BASE_URI();

    return {
        %{ $self->SUPER::_CONFIG() },
        authorize_uri    => "$base_uri/oauth/authorize",
        access_token_uri => "$base_uri/api/oauth.access",
        user_info_uri    => "$base_uri/api/users.identity",    #not used
    };
}

# This function returns the required configuration fields for the provider module. This should be overridden if your provider requires different information.
sub _CONFIG_FIELDS {
    my ($self) = @_;

    my $client_config = $self->get_client_configuration();

    return {
        'client_id' => {
            'label'         => 'App ID',
            'description'   => 'The ID of the Slack Application',
            'value'         => $client_config->{client_id},
            'display_order' => 0,
        },
        'client_secret' => {
            'label'         => 'App Secret',
            'description'   => 'The Secret of the Slack Application',
            'value'         => $client_config->{client_secret},
            'display_order' => 1,
        },
    };
}

=head2 get_id_token( TOKEN_OBJ )

See external authn docs.

=cut

#OAuth2 doesn’t have ID tokens, so we provide a mocked one.
sub get_id_token {
    my ( $self, $oidc_lite_client_token_obj_or_id_token_string ) = @_;

    if ( !ref $oidc_lite_client_token_obj_or_id_token_string ) {
        return $self->SUPER::get_id_token($oidc_lite_client_token_obj_or_id_token_string);
    }

    my $ct_obj = $oidc_lite_client_token_obj_or_id_token_string;

    #User ID alone is not guaranteed to be unique;
    #only user+team is unique.
    #cf. https://api.slack.com/methods/users.identity
    my $id = "user-$ct_obj->{'user'}{'id'}-team-$ct_obj->{'team'}{'id'}";

    $self->_load_modules(qw( OIDC::Lite::Model::IDToken ));

    my $decoded = $self->get_user_info($ct_obj);

    my $id_token = OIDC::Lite::Model::IDToken->new(
        'header' => {
            'kid' => '1',
            'alg' => 'none',
            'typ' => 'JWT'
        },
        'payload' => {
            'sub'     => $id,
            'name'    => $decoded->{'name'},
            'picture' => $decoded->{'picture'},
        },
        'key' => undef,
    );
    $id_token->get_token_string();    # ensure we create the string
    return $id_token;
}

=head2 get_user_info( TOKEN_OBJ )

See external authn docs.

=cut

#Slack returns the information we need in the payload of oauth.access.
sub get_user_info {
    my ( $self, $access_token_obj ) = @_;

    my $user_hr = $access_token_obj->{'user'};

    my @image_sizes = map { m<\Aimage_(.+)> ? $1 : () } keys %$user_hr;

    my $biggest_size = ( sort { $a <=> $b } @image_sizes )[-1];

    return {
        name  => $user_hr->{'name'},
        email => $user_hr->{'email'},
        ( @image_sizes ? ( picture => $user_hr->{"image_$biggest_size"} ) : () ),
    };
}

1;
