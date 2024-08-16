package Cpanel::Wrap::Config;

# cpanel - Cpanel/Wrap/Config.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our %ALLOWED_ENV = (
    'REMOTE_PASSWORD'      => 1,    #TEMP_SESSION_SAFE
    'REMOTE_ADDR'          => 1,
    'HTTP_COOKIE'          => 1,    #Needed for locales, Cpanel::AdminBin::Server will filter out any key other than session_locale
    'CPRESELLER'           => 1,
    'CPRESELLERSESSION'    => 1,
    'CPRESELLERSESSIONKEY' => 1,
    'WHM50'                => 1,
    'cp_security_token'    => 1,
    'APITOOL'              => 1,
    'TEAM_USER'            => 1,
    'TEAM_OWNER'           => 1,
    'TEAM_LOGIN_DOMAIN'    => 1,
);

sub safe_hashref_of_allowed_env {
    return { map { $ALLOWED_ENV{$_} ? ( $_ => substr( $ENV{$_} || '', 0, 1024 ) ) : () } keys %ENV };
}

1;
