package Cpanel::Branding::Detect;

# cpanel - Cpanel/Branding/Detect.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Branding::Lite::Package ();
use Cpanel::MobileAgent             ();
my $didautodetect;

sub autodetect_mobile_browser {
    if ( !$didautodetect && $Cpanel::CPDATA{'RS'} && -e '/usr/local/cpanel/base/frontend/' . $Cpanel::CPDATA{'RS'} . '/branding/mobile' && Cpanel::MobileAgent::is_mobile_agent( $ENV{'HTTP_USER_AGENT'} ) ) {
        Cpanel::Branding::Lite::Package::_tempsetbrandingpkg('mobile');
        ( $didautodetect, $Cpanel::CPVAR{'mobile'} ) = ( 1, 1 );
    }
    return 1;
}
1;
