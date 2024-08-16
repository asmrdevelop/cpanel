package Cpanel::PwUtils;

# cpanel - Cpanel/PwUtils.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Exception ();
use Cpanel::PwCache   ();

#Pass in a user or UID, and this returns a UID.
sub normalize_to_uid {
    my ($user) = @_;

    if ( !length $user ) {
        die Cpanel::Exception::create( 'MissingParameter', 'Supply a username or a user ID.' );
    }

    return $user if $user !~ tr{0-9}{}c;    # Only has numbers so its a uid

    # We detect scalar context and avoid reading shadow
    # however we are being explict here by calling
    # getpwnam_noshadow.
    my $uid = Cpanel::PwCache::getpwnam_noshadow($user);
    if ( !defined $uid ) {
        die Cpanel::Exception::create( 'UserNotFound', [ name => $user ] );
    }

    return $uid;
}

1;
