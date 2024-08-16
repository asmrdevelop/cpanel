package Cpanel::API::Contactus;

# cpanel - Cpanel/API/Contactus.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Branding::Lite  ();
use Cpanel::CachedDataStore ();

our $contactus_cfg_ref;

sub is_enabled {
    my ( $args, $result ) = @_;
    if ( $Cpanel::appname eq 'webmail' ) {
        $result->data( { enabled => 0 } );
        return 1;
    }
    $contactus_cfg_ref ||= _get_contactus_info();
    my $enabled = ( exists $contactus_cfg_ref->{'contacttype'} && $contactus_cfg_ref->{'contacttype'} eq 'disable' ) ? 0 : 1;
    $result->data( { enabled => $enabled } );
    return 1;
}

sub _get_contactus_info {
    my $branding_dir = Cpanel::Branding::Lite::_get_contactinfodir();
    return Cpanel::CachedDataStore::fetch_ref( $branding_dir . '/contactinfo.yaml' ) || {};
}

our %API = (
    is_enabled => { allow_demo => 1 },
);

1;
