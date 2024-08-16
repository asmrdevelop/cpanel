package Cpanel::SafeDir::MKAsUser;

# cpanel - Cpanel/SafeDir/MKAsUser.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::PwCache::Get                 ();
use Cpanel::AccessIds::ReducedPrivileges ();
use Cpanel::SafeDir::MK                  ();

#
# Make the directory as the specified user, if run as root
# or as the specified user.
# This assumes the $path is legit and untaints the given path.
#
# die()s on an attempt to setuid as a normal user to a different user.
#
# Returns the same values as safemkdir().
#
sub safemkdir_as_user {
    my ( $user, $path, $mode ) = @_;

    my $uid = Cpanel::PwCache::Get::getuid($user);

    my $reduced_privs;
    if ( $> ne $uid ) {

        #This will die() if attempted as a user.
        $reduced_privs = Cpanel::AccessIds::ReducedPrivileges->new($uid);
    }

    $path =~ /^(.*)$/;
    $path = $1;

    return Cpanel::SafeDir::MK::safemkdir( $path, $mode );
}

1;
