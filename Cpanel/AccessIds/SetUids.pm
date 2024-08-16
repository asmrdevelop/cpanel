package Cpanel::AccessIds::SetUids;

# cpanel - Cpanel/AccessIds/SetUids.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cpanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::AccessIds::SetUids - conveniences for setuid operations

=head1 SYNOPSIS

    Cpanel::AccessIds::SetUids::setuids( 'bob' );
    Cpanel::AccessIds::SetUids::setuids( 'bob', 'bob', 'group1' );

=head1 FUNCTIONS

=cut

use Cpanel::Debug                ();
use Cpanel::AccessIds::Utils     ();
use Cpanel::AccessIds::Normalize ();
use Cpanel::Sys::Id              ();

our $VERSION = '1.3';

=head2 setuids( USERNAME_OR_UID, [GROUPNAME_OR_GID1], [SUPPLIMENTAL_GROUPNAME_OR_GID], ... )

Drops EUID and RUID to the given username or UID, RGID to
the first-given group, and EGID to all of the given groups.

If no groups are given, then RGID and EGID are set to the group with the same
name as the given user.

Note that this means if you want to drop privileges to a user but retain
an additional group, you need to specify the user’s group in addition
to the “additional” group. (See the “bob”/“group1” example above.)

This parses the given parameters to determine if each is a name or
an ID. This means that any users whose names might be fully numeric won’t
work with this function. But you shouldn’t have such usernames in the first
place, so hey. :-P

=cut

sub setuids {    ## no critic qw(RequireArgUnpacking)
    my ( $uid, $gid, @additional_gids ) = Cpanel::AccessIds::Normalize::normalize_user_and_groups(@_);
    if ( 'Cpanel::PwCache::Cache'->can('pwmksafecache') ) {    # PPI NO PARSE - will not fail if not loaded
        Cpanel::PwCache::Cache::pwmksafecache();               # PPI NO PARSE - nothing to do if the can is false
    }

    if ( !defined $uid || !defined $gid ) {
        Cpanel::Debug::log_die("setuids failed: Could not resolve UID or GID (@_)");
    }

    # Note: cannot use Try::Tiny here as performance is extermely
    # senstive here
    local $@;
    eval { Cpanel::Sys::Id::setgroups( $gid, @additional_gids ); };
    if ($@) {
        _log_and_die_if_not_root() or die;
    }

    eval { Cpanel::Sys::Id::setresgid( $gid, $gid, $gid ); };
    if ($@) {
        _log_and_die_if_not_root() or die;
    }

    Cpanel::AccessIds::Utils::validate_var_set( 'EGID', join( ' ', $gid, @additional_gids ? ( @additional_gids, $gid ) : ($gid) ), $) );
    Cpanel::AccessIds::Utils::validate_var_set( 'RGID', join( ' ', $gid, @additional_gids ? ( @additional_gids, $gid ) : ($gid) ), $( );

    eval { Cpanel::Sys::Id::setresuid( $uid, $uid, $uid ); };
    if ($@) {
        _log_and_die_if_not_root() or die;
    }

    Cpanel::AccessIds::Utils::validate_var_set( 'EUID', $uid, $< );
    Cpanel::AccessIds::Utils::validate_var_set( 'RUID', $uid, $> );

    return $uid;
}

sub _log_and_die_if_not_root {
    if ( $< != 0 ) {
        Cpanel::Debug::log_die("setuids failed: Attempting to setuid as a normal user with RUID $<");
    }

    if ( $> != 0 ) {
        Cpanel::Debug::log_die("setuids failed: Attempting to setuid as a normal user with EUID $>");
    }
    return 0;
}

1;
