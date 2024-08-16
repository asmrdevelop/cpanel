package Cpanel::Quota::OverCache;

# cpanel - Cpanel/Quota/OverCache.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Quota::Overcache - A cache for whether a user is over quota.

=head1 SYNOPSIS

    use Cpanel::Quota::OverCache;

    my @users = Cpanel::Quota::OverCache::get_users_at_blocks_quota();

    #NB: This does NOT check anything other than the cache. Don’t rely
    #solely on this information if you want it to be accurate as to the
    #actual system state.
    my $is_at_quota = Cpanel::Quota::OverCache::user_is_at_blocks_quota('bob');

    Cpanel::Quota::OverCache::set_user_at_blocks_quota('hank');
    Cpanel::Quota::OverCache::unset_user_at_blocks_quota('hank');

=head1 NOTES

It is conceived that we may want to expand this module to include inodes
quota caching as well.

=cut

use strict;
use warnings;

use Try::Tiny;

#Please keep this module small! It gets used in cpsrvd.
use Cpanel::Autodie                 ();
use Cpanel::Context                 ();
use Cpanel::LoadModule              ();
use Cpanel::Quota::OverCache::Check ();

our $QUOTA_CACHE_DIR_PERMS = 0711;    # case CPANEL-8586: must be stat()able as the user

sub get_users_at_blocks_quota {
    Cpanel::Context::must_be_list();

    Cpanel::LoadModule::load_perl_module('Cpanel::FileUtils::Read');
    _ensure_cache_dir_exists();

    my @users;

    'Cpanel::FileUtils::Read'->can('for_each_directory_node')->(
        $Cpanel::Quota::OverCache::Check::_DIR,
        sub {
            return if !m<\Ablocks_(.+)>;
            push @users, $1;
        },
    );

    return @users;
}

#This die()s if the user is already set.
sub set_user_at_blocks_quota {
    my ( $username, $used, $limit ) = @_;

    return _set_at_quota( 'blocks', $username, $used, $limit );
}

#Returns 1 if the quota flag was set before.
#Returns 0 if the quota flag was NOT set before (i.e., this was a no-op).
sub unset_user_at_blocks_quota {
    my ($username) = @_;

    return _unset_at_quota( 'blocks', $username );
}

#----------------------------------------------------------------------

sub _unset_at_quota {
    my ( $_what, $username ) = @_;

    #Just in case.
    Cpanel::Quota::OverCache::Check::_check_username($username);

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');

    return try {
        Cpanel::Autodie::unlink_if_exists("$Cpanel::Quota::OverCache::Check::_DIR/${_what}_$username");
    }
    catch {
        if ( !try { $_->error_name eq 'EACCES' } ) {
            local $@ = $_;
            die;
        }
    };
}

sub _set_at_quota {
    my ( $_what, $username, $used, $limit ) = @_;

    die "Need used ($_what)!"  if !$used;
    die "Need limit ($_what)!" if !$limit;

    #Just in case.
    Cpanel::Quota::OverCache::Check::_check_username($username);

    Cpanel::LoadModule::load_perl_module('Cpanel::Autodie');
    Cpanel::LoadModule::load_perl_module('Cpanel::Time::ISO');

    _ensure_cache_dir_exists();

    #The “payload” of this symlink doesn’t really matter at this point
    #because nothing actually reads this information. We could just make these
    #touch files instead of symlinks; this is a reworking, though, of logic
    #that stored the timestamp and usage/limit information in file contents.
    #(Those contents were just never actually used!) Anyhow, it seems best
    #to continue saving this information in case it’s useful later.
    Cpanel::Autodie::symlink(
        join(
            '_',
            'Cpanel::Time::ISO'->can('unix2iso')->(),
            $used,
            $limit,
        ),
        "$Cpanel::Quota::OverCache::Check::_DIR/${_what}_$username",
    );

    return;
}

sub _ensure_cache_dir_exists {
    Cpanel::Autodie::exists_nofollow($Cpanel::Quota::OverCache::Check::_DIR);
    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');
    Cpanel::Mkdir::ensure_directory_existence_and_mode( $Cpanel::Quota::OverCache::Check::_DIR, $QUOTA_CACHE_DIR_PERMS );
    return 1;
}

1;
