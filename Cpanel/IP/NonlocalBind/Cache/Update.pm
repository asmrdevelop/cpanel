package Cpanel::IP::NonlocalBind::Cache::Update;

# cpanel - Cpanel/IP/NonlocalBind/Cache/Update.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Write        ();
use Cpanel::IP::NonlocalBind::Cache ();
use Cpanel::IP::NonlocalBind        ();

=encoding utf-8

=head1 NAME

Cpanel::IP::NonlocalBind::Cache::Update - Update the ipv4_ip_nonlocal_bind cache file

=head1 SYNOPSIS

    use Cpanel::IP::NonlocalBind::Cache::Update ();

    Cpanel::IP::NonlocalBind::Cache::Update::update();

=head2 update()

Updates the Cpanel::IP::NonlocalBind::Cache::CACHE_FILE on the disk
to reflect the state of the 'net.ipv4.ip_nonlocal_bind' as returned
by Cpanel::IP::NonlocalBind::ipv4_ip_nonlocal_bind_is_enabled()

The cache file will be empty if 'net.ipv4.ip_nonlocal_bind' zero,
the cache file will contain the string '1' if  'net.ipv4.ip_nonlocal_bind'
is 1.  If 'net.ipv4.ip_nonlocal_bind' cannot be determined, the cache
file will contain the string '22' as this ensures that we err on the
side of caution and do the slow check in Cpanel::IP::Bound::ipv4_is_bound

Currently we update this cache file when the global cache is built
via /usr/local/cpanel/bin/build_global_cache

=cut

sub update {
    my $is_enabled = Cpanel::IP::NonlocalBind::ipv4_ip_nonlocal_bind_is_enabled();

    my $file_contents = !defined $is_enabled ? 'UNKNOWN' : $is_enabled ? 'ENABLED' : 'DISABLED';
    $file_contents = Cpanel::IP::NonlocalBind::Cache->$file_contents();

    return Cpanel::FileUtils::Write::overwrite(
        $Cpanel::IP::NonlocalBind::Cache::CACHE_FILE,
        $file_contents,
        0644
    );
}
1;
