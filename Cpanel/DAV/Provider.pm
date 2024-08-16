package Cpanel::DAV::Provider;

# cpanel - Cpanel/DAV/Provider.pm                  Copyright 2024 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant 'OVERRIDE_FILE' => "/var/cpanel/calendarserver";

use Cpanel::LoadFile::ReadFast ();

=head1 NAME

Cpanel::DAV:Provider

=head1 DESCRIPTION

Module for determining what calendar server is installed.

=head1 SUBROUTINES

=head2 installed

Returns the installed CALDAV/CARDDAV provider.

=cut

sub installed {
    my $dav_provider = 'CPDAVD';    # The new default

    # Also allow the caller to override this to bring in the driver they want.
    if ( -s OVERRIDE_FILE ) {
        $dav_provider = '';
        open( my $ofh, "<", OVERRIDE_FILE ) || die 'Failed to open ' . OVERRIDE_FILE . " for reading: $!";
        Cpanel::LoadFile::ReadFast::read_all_fast( $ofh, $dav_provider, -s _ );
        chomp($dav_provider);
    }

    return $dav_provider;
}

1;
