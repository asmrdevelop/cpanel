package Cpanel::IP::NonlocalBind::Cache;

# cpanel - Cpanel/IP/NonlocalBind/Cache.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::IP::NonlocalBind::Cache - Check to see if ipv4 ip_nonlocal_bind is enabled via a cache file

=head1 SYNOPSIS

    use Cpanel::IP::NonlocalBind::Cache;

    my $enabled = Cpanel::IP::NonlocalBind::Cache::ipv4_ip_nonlocal_bind_is_enabled();

=cut

use constant {
    DISABLED => '',    # 0-bytes
    ENABLED  => 1,     # 1-byte
    UNKNOWN  => 22,    # 2-bytes

    _ENOENT => 2,
};

our $CACHE_FILE = '/var/cpanel/ipv4_ip_nonlocal_bind';

our $_ipv4_ip_nonlocal_bind_cache_length;

=head2 ipv4_ip_nonlocal_bind_is_enabled

Determine the cached value of the 'net.ipv4.ip_nonlocal_bind' sysctl.
It returns 1 or 0 to indicate that, or undef if it can’t be determined.

The cache file is currently being updated when the global
cache is built by calling Cpanel::IP::NonlocalBind::Cache::Update::update()

=cut

sub ipv4_ip_nonlocal_bind_is_enabled {

    # Note that we report these two cases the same way:
    #
    #   - Cache file exists but indicates UNKNOWN status.
    #   - Cache file does not exist.
    #
    # We reserve the right to change how one of these is reported
    # in the future.

    if ( !defined $_ipv4_ip_nonlocal_bind_cache_length ) {
        $_ipv4_ip_nonlocal_bind_cache_length = ( stat($CACHE_FILE) )[7];

        if ( !defined $_ipv4_ip_nonlocal_bind_cache_length ) {
            if ( $! != _ENOENT() ) {
                warn "stat($CACHE_FILE): $!";
            }
        }
    }

    if ( defined $_ipv4_ip_nonlocal_bind_cache_length ) {
        return 1 if $_ipv4_ip_nonlocal_bind_cache_length == length ENABLED();
        return 0 if $_ipv4_ip_nonlocal_bind_cache_length == length DISABLED();

        if ( $_ipv4_ip_nonlocal_bind_cache_length != length UNKNOWN() ) {
            warn "“$CACHE_FILE” has unrecognized length: $_ipv4_ip_nonlocal_bind_cache_length";
        }
    }

    return undef;
}

1;
