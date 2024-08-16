package Cpanel::LicenseAuthn;

# cpanel - Cpanel/LicenseAuthn.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Try::Tiny;

use Cpanel::Context  ();
use Cpanel::JSON     ();
use Cpanel::LoadFile ();

#overridden in tests
our $_CONFIG_FILE_PATH = '/var/cpanel/licenseid_credentials.json';

#Returns empty if there is nothing saved.
sub get_id_and_secret {
    my ($tenant) = @_;

    Cpanel::Context::must_be_list();

    die 'Missing a tenant name! (“cpanel”?)' if !length $tenant;

    my $cfg;
    try {
        $cfg = Cpanel::JSON::Load( Cpanel::LoadFile::load($_CONFIG_FILE_PATH) );
    }
    catch {
        if ( !try { $_->isa('Cpanel::Exception::IO::FileNotFound') } && !try { $_->error_name eq 'EACCES' } ) {
            local $@ = $_;
            die;
        }
    };

    if ($cfg) {

        $tenant .= '.';

        #For some reason these credentials are sent not-quite-complete;
        #they need the provisioning prefix in order to work.
        for (qw( client_id  client_secret )) {
            substr( $cfg->{$_}, 0, 0, $tenant );
        }

        return @{$cfg}{qw( client_id  client_secret )};
    }

    return;
}

1;
