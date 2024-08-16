package Cpanel::PwCache::CurrentUser;

# cpanel - Cpanel/PwCache/CurrentUser.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::PwCache::Load ();

=encoding utf-8

=head1 NAME

Cpanel::PwCache::CurrentUser - Load the password cache for the currently logged in user

=head1 SYNOPSIS

    use Cpanel::PwCache::CurrentUser;

    Cpanel::PwCache::CurrentUser::prime_cache();

    my $homedir = Cpanel::PwCache::gethomedir();

=head1 DESCRIPTION

This modules loads the password cache from /var/cpanel/user_pw_cache
in order to avoid having to search /etc/passwd.

=head1 SECURITY

The files in /var/cpanel/user_pw_cache/ are only readable by
root:gid of the user that the cache is for.  No passwords
are ever contained in these caches.  An invalid
or faked $ENV{'CURRENT_USER_UID'} is not considered to be
a security concern.

=head2 prime_cache

This funciton will load the password cache for the currently
logged in user to ensure calls to Cpanel::PwCache do not have
to examine /etc/passwd when looking up a user.

It will determine the cache to load by checking the following
variables in order:

    $ENV{'REMOTE_USER'}
    $ENV{'CURRENT_USER_UID'}
    $>

In the event this code is run as root and the logged in user
is not root, it will also load the cache for root.

=cut

sub prime_cache {

    # $ENV{'CURRENT_USER_UID'} is set by cpsrvd
    my $uid_is_from_env     = ( length $ENV{'CURRENT_USER_UID'} && $ENV{'CURRENT_USER_UID'} !~ tr{0-9}{}c ) ? 1 : 0;
    my $remote_user_is_root = ( length $ENV{'REMOTE_USER'}      && $ENV{'REMOTE_USER'} eq 'root' )          ? 1 : 0;
    my $current_uid         = $>;
    my $file_uid            = ( $remote_user_is_root ? 0 : $uid_is_from_env ? $ENV{'CURRENT_USER_UID'} : $current_uid );

    my $username_from_pw_cache;
    my $userpwcache_file = '/var/cpanel/user_pw_cache/' . $file_uid;
    if ( -e $userpwcache_file ) {
        my ( $passwduid, $passwdmtime ) = ( stat(_) )[ 4, 9 ];
        local $@;
        eval { $username_from_pw_cache = Cpanel::PwCache::Load::load_pw_cache_file( $userpwcache_file, $passwduid, $passwdmtime ); };    # if this fails we will get it another way
    }

    # If we are running as root and not logged in as root
    # we need to prime the pwcache for root as well
    if ( $current_uid == 0 && $file_uid != $current_uid ) {
        $userpwcache_file = '/var/cpanel/user_pw_cache/0';
        my ( $passwduid, $passwdmtime ) = ( stat($userpwcache_file) )[ 4, 9 ];
        eval { Cpanel::PwCache::Load::load_pw_cache_file( $userpwcache_file, $passwduid, $passwdmtime ); };    # if this fails we will get it another way
    }

    return $username_from_pw_cache;
}

1;
