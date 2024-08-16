package Cpanel::Security::Authn::OIDCConfigCache;

# cpanel - Cpanel/Security/Authn/OIDCConfigCache.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This handles the loading of the OpenID Connent “well-known configuration”.
#
# Its methods accept two parameters: the provider name, and the URI from
# which to obtain the configuration data.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw(Cpanel::CacheFile);

use Cpanel::LoadModule              ();
use Cpanel::JSON                    ();
use Cpanel::Security::Authn::Config ();

sub _PATH {
    my ( $self, $provider_name ) = @_;

    die "Need provider name!" if !length $provider_name;

    return sprintf(
        "%s/.%s.well_known_config",
        $Cpanel::Security::Authn::Config::OPEN_ID_CLIENT_CONFIG_DIR,
        $provider_name,
    );
}

sub _TTL { return $Cpanel::Security::Authn::Config::MAX_CONFIG_CACHE_AGE }

#User-readable.
sub _MODE { return 0644 }

sub _LOAD_FRESH {
    my ( $self, $provider_name, $uri ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::HTTP::Client');

    my $http = Cpanel::HTTP::Client->new()->die_on_http_error();

    return Cpanel::JSON::Load( $http->get($uri)->content() );
}

1;
