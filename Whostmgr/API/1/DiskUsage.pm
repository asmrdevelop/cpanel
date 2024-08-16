package Whostmgr::API::1::DiskUsage;

# cpanel - Whostmgr/API/1/DiskUsage.pm               Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Config::LoadCpConf     ();
use Cpanel::Config::Users          ();
use Cpanel::Exception              ();
use Cpanel::Quota                  ();
use Cpanel::SysQuota               ();
use Whostmgr::ACLS                 ();
use Whostmgr::AcctInfo::Owner      ();
use Whostmgr::API::1::Data::Filter ();
use Whostmgr::API::1::Utils        ();
use Whostmgr::Authz                ();

use constant NEEDS_ROLE => {
    get_disk_usage => undef,
};

=encoding utf-8

=head1 NAME

Whostmgr::API::1::DiskUsage - Obtain disk usage and quota limits

=head1 SYNOPSIS

    use Whostmgr::API::1::DiskUsage;

    Whostmgr::API::1::DiskUsage::get_disk_usage({}, {});

=head2 get_disk_usage

A thin wrapper around fetching system quota data.

=cut

sub get_disk_usage {
    my ( $args, $metadata, $api_args ) = @_;

    my $cache_mode = $args->{'cache_mode'} // 'on';

    state %SKIP_CACHE = (
        on  => 0,
        off => 1,
    );

    my $skip_cache_yn = $SKIP_CACHE{$cache_mode} // do {
        $metadata->set_not_ok("Invalid “cache_mode”: “$args->{'cache_mode'}”");
        return;
    };

    my ( $gave_multi_users, $username ) = _apply_filters($api_args);

    my @usages;
    if ( !$gave_multi_users ) {
        if ($username) {
            @usages = _get_one_user_disk_usage($username);
        }
        else {
            my ( $qrused, $qrlimit, $version, $inodes_used, $inodes_limit ) = Cpanel::SysQuota::analyzerepquotadata( skip_cache => $skip_cache_yn );

            if ( !$qrused ) {
                die Cpanel::Exception::create( 'Quota::NotEnabled', 'Filesystem quotas are disabled.' );
            }

            my @cpusers = Cpanel::Config::Users::getcpusers();
            if ( !Whostmgr::ACLS::hasroot() ) {
                @cpusers = grep { Whostmgr::AcctInfo::Owner::checkowner( $ENV{'REMOTE_USER'}, $_ ) } @cpusers;
            }

            @usages = map {
                {
                    'blocks_used'  => $qrused->{$_},          #
                    'blocks_limit' => $qrlimit->{$_},         #
                    'inodes_used'  => $inodes_used->{$_},     #
                    'inodes_limit' => $inodes_limit->{$_},    #
                    'user'         => $_,
                }
            } @cpusers;
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return {
        'accounts' => \@usages,
    };
}

my $BYTES_TO_BLOCKS = 1024;

sub _get_one_user_disk_usage {
    my ($user) = @_;

    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();

    local $@;
    return if !eval { Whostmgr::Authz::verify_account_access($user); 1 };

    my ( $used, $limit, $remain, $inodes_used, $inodes_limit, $inodes_remain ) = Cpanel::Quota::displayquota(
        {
            'user'          => $user,                                      #
            bytes           => 1,                                          #
            include_mailman => $cpconf->{'disk_usage_include_mailman'},    #
            include_sqldbs  => $cpconf->{'disk_usage_include_sqldbs'}      #
        }
    );

    if ( $used && $used eq $Cpanel::Quota::QUOTA_NOT_ENABLED_STRING ) {
        die Cpanel::Exception::create( 'Quota::NotEnabled', 'Filesystem quotas are disabled.' );
    }
    return {
        'user'         => $user,
        'blocks_used'  => $used / $BYTES_TO_BLOCKS,                                   #
        'blocks_limit' => defined $limit ? ( $limit / $BYTES_TO_BLOCKS ) : $limit,    #
        'inodes_used'  => $inodes_used,                                               #
        'inodes_limit' => $inodes_limit                                               #
    };
}

sub _apply_filters {
    my ($api_args) = @_;
    my @filters = Whostmgr::API::1::Data::Filter::get_filters($api_args);

    my $username;
    my $gave_multi_users;

    for my $filter (@filters) {
        my ( $field, $type, $term ) = @$filter;
        if ( ( $field eq 'user' ) && ( $type eq 'eq' ) ) {
            Whostmgr::API::1::Data::Filter::mark_filters_done( $api_args, $filter );

            if ( defined $username ) {
                $gave_multi_users ||= ( $username ne $term );
            }
            else {
                $username = $term;
            }
        }
    }
    return ( $gave_multi_users, $username );
}

1;
