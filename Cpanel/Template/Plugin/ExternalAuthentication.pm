package Cpanel::Template::Plugin::ExternalAuthentication;

# cpanel - Cpanel/Template/Plugin/ExternalAuthentication.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::App                            ();
use Cpanel::Security::Authn::Config        ();
use Cpanel::Security::Authn::OpenIdConnect ();

sub new {
    my ($class) = @_;

    return bless {}, $class;
}

sub get_enabled_and_configured_openid_provider_display_configurations {
    if ( grep { $Cpanel::App::appname eq $_ } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
        return Cpanel::Security::Authn::OpenIdConnect::get_enabled_openid_provider_display_configurations($Cpanel::App::appname);
    }
    return;
}

1;
