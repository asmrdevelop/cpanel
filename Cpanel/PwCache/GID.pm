package Cpanel::PwCache::GID;

# cpanel - Cpanel/PwCache/GID.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadFile::ReadFast ();
use Cpanel::PwCache::Helpers   ();

sub get_gid_cacheref {

    if ( $INC{'B/C.pm'} ) {
        Cpanel::PwCache::Helpers::confess("Cpanel::PwCache::get_gid_cacheref cannot be run under B::C (see case 162857)");
    }

    my $SYSTEM_CONF_DIR = Cpanel::PwCache::Helpers::default_conf_dir();
    my $fh;
    open( $fh, '<:stdio', "$SYSTEM_CONF_DIR/group" ) or die "Failed to open $SYSTEM_CONF_DIR/group: $!";
    my $data = '';
    Cpanel::LoadFile::ReadFast::read_all_fast( $fh, $data );
    return { map { my $s = [ split( /:/, $_ ) ]; defined $s->[2] ? ( $s->[2] => $s ) : () } split( /\n/, $data ) };
}

1;
