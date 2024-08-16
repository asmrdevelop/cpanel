package Cpanel::PwCache::Get;

# cpanel - Cpanel/PwCache/Get.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::PwCache ();

my %PW_INDEX;

BEGIN {
    my @PW_ORDER = qw(
      name
      passwd
      uid
      gid
      quota
      comment
      gcos
      dir
      shell
      expire
    );
    %PW_INDEX = map { $PW_ORDER[$_] => $_ } ( 0 .. $#PW_ORDER );
}

#NOTE: As of July 2013, we treat the passwd shell entry as authoritative over the cpuser entry.
#At some later point we'll want to switch to using the cpuser file as the authoritative source,
#but until then this function should do it.

sub getshell {    ## no critic qw(RequireArgUnpacking)
    return _get_sth_from_pw_for_user( 'shell', @_ );
}

sub getuid {    ## no critic qw(RequireArgUnpacking)
    return _get_sth_from_pw_for_user( 'uid', @_ );
}

sub getgid {    ## no critic qw(RequireArgUnpacking)
    return _get_sth_from_pw_for_user( 'gid', @_ );
}

sub _get_sth_from_pw_for_user {
    my ( $what_to_get, $user ) = @_;

    if ( !defined $user ) {
        $user = $>;
    }

    if ( $user !~ tr{0-9}{}c ) {    # contains only numerals
        return scalar( ( Cpanel::PwCache::getpwuid_noshadow($user) )[ $PW_INDEX{$what_to_get} ] );
    }

    return scalar( ( Cpanel::PwCache::getpwnam_noshadow($user) )[ $PW_INDEX{$what_to_get} ] );
}

1;
