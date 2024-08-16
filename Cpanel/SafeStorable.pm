package Cpanel::SafeStorable;

# cpanel - Cpanel/SafeStorable.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Storable ();

our $VERSION = '1.00';

*nstore      = *Storable::nstore;
*store       = *Storable::store;
*store_fd    = *Storable::store_fd;
*nstore_fd   = *Storable::nstore_fd;
*freeze      = *Storable::freeze;
*nfreeze     = *Storable::nfreeze;
*lock_store  = *Storable::lock_store;
*lock_nstore = *Storable::lock_nstore;
*file_magic  = *Storable::file_magic;
*read_magic  = *Storable::read_magic;
*retrieve_fd = *fd_retrieve;

sub dclone {

    # we need to be sure that dclone will return an object
    local $Storable::flags = 6;
    goto &Storable::dclone;
}

sub thaw {
    return Storable::thaw( $_[0], 0 );
}

sub retrieve {
    return Storable::retrieve( $_[0], 0 );
}

sub fd_retrieve {
    return Storable::fd_retrieve( $_[0], 0 );
}

sub lock_retrieve {
    return Storable::lock_retrieve( $_[0], 0 );
}

1;
