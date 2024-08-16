package Cpanel::Security::Authn::Provider::Google;

# cpanel - Cpanel/Security/Authn/Provider/Google.pm
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

use parent 'Cpanel::Security::Authn::Provider::OpenIdConnectBase';

my $image = <<SVG;
PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIyMiIgaGVp
Z2h0PSIxNCIgdmlld0JveD0iMCAwIDIyIDE0Ij48ZyBmaWxsPSIjZmZmIiBmaWxsLXJ1bGU9
ImV2ZW5vZGQiPjxwYXRoIGQ9Ik03IDZ2Mi40aDMuOTdjLS4xNiAxLjAzLTEuMiAzLjAyLTMu
OTcgMy4wMi0yLjM5IDAtNC4zNC0xLjk4LTQuMzQtNC40MlM0LjYxIDIuNTggNyAyLjU4YzEu
MzYgMCAyLjI3LjU4IDIuNzkgMS4wOGwxLjktMS44M0MxMC40Ny42OSA4Ljg5IDAgNyAwIDMu
MTMgMCAwIDMuMTMgMCA3czMuMTMgNyA3IDdjNC4wNCAwIDYuNzItMi44NCA2LjcyLTYuODQg
MC0uNDYtLjA1LS44MS0uMTEtMS4xNkg3ek0yMiA2aC0yVjRoLTJ2MmgtMnYyaDJ2MmgyVjho
MiIvPjwvZz48L3N2Zz4=
SVG

sub _DISPLAY_NAME          { return 'Google'; }
sub _PROVIDER_NAME         { return 'google'; }
sub _WELL_KNOWN_CONFIG_URI { return 'https://accounts.google.com/.well-known/openid-configuration'; }
sub _DOCUMENTATION_URL     { return 'https://developers.google.com/identity/protocols/OpenIDConnect'; }

sub _BUTTON_COLOR      { return 'dd4b39'; }
sub _BUTTON_TEXT_COLOR { return 'FFFFFF'; }

sub _BUTTON_ICON { return $image; }

sub _CAN_VERIFY { return 1; }

1;
