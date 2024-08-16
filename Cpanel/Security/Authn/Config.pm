package Cpanel::Security::Authn::Config;

# cpanel - Cpanel/Security/Authn/Config.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::ConfigFiles ();

our $VERSION                      = '1.1';
our %SUPPORTED_PROTOCOLS          = qw( openid_connect 1 );
our @ALLOWED_SERVICES             = qw( cpaneld webmaild whostmgrd );
our $AUTHN_LINK_DB_DIRECTORY_BASE = '/var/cpanel/authn/links';
our $AUTHN_USER_DB_DIRECTORY      = '/var/cpanel/authn/links/users';

our $CPANEL_AUTHN_CONFIG_DIR          = '/var/cpanel/authn';
our $OIDC_AUTHENTICATION_CONFIG_DIR   = '/var/cpanel/authn/openid_connect';
our $AUTHENTICATION_CLIENT_CONFIG_DIR = '/var/cpanel/authn/client_config';
our $OPEN_ID_CLIENT_CONFIG_DIR        = '/var/cpanel/authn/client_config/openid_connect';
our $PROVIDER_MODULE_DIR              = '/Cpanel/Security/Authn/Provider';

our @PROVIDER_MODULE_SEARCH_ROOTS = (
    $Cpanel::ConfigFiles::CPANEL_ROOT,
    $Cpanel::ConfigFiles::CUSTOM_PERL_MODULES_DIR,
);

our $MAX_CONFIG_CACHE_AGE            = 86400;          # One day
our $DEFAULT_ACCESS_TOKEN_EXPIRES_IN = ( 60 * 60 );    # One hour

our $CLIENT_CONFIG_DIR_PERMS   = 0711;                 # Must be readable to so the user can see if the provider is configured
our $CLIENT_CONFIG_FILE_PERMS  = 0600;                 # Must not be readable because it contains the key
our $DISPLAY_CONFIG_FILE_PERMS = 0644;
our $LOGIN_DB_DIR_PERMS        = 0700;

1;
