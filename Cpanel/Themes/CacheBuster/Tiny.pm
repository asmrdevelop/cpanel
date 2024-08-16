package Cpanel::Themes::CacheBuster::Tiny;

# cpanel - Cpanel/Themes/CacheBuster/Tiny.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#
# The purpose of this module is to provide a CacheBusting mechanism suitable for
# use in the cPanel interface.

use strict;
use warnings;

use Cpanel::PwCache ();
use Cpanel::Debug   ();
use Try::Tiny;

=encoding utf-8

=head1 NAME

Cpanel::Themes::CacheBuster::Tiny - Tool to reset the cPanel interface's cache

=head1 SYNOPSIS

    use Cpanel::Themes::CacheBuster::Tiny;

    Cpanel::Themes::CacheBuster::Tiny::reset_cache_id();

=head1 DESCRIPTION

Tool to reset the cache in the cPanel interface. The cache_id is included
in the urls generated in the cPanel interface and is used to ensure that
changes are seen as soon as the cache_id is changed.

=cut

=head2 reset_cache_id

Reset the cache id the cPanel interface. This function must be run with the uid of the user to reset the cache_id for.

=over 2

=item Input

None

=item Output

=over 3

=item C<SCALAR>

    The new cache id.

=back

=back

=cut

sub reset_cache_id {
    my $cache_id_file = _get_cache_id_file();

    my $cache_id_time = time();
    try {
        require Cpanel::FileUtils::Write;
        Cpanel::FileUtils::Write::overwrite( $cache_id_file, $cache_id_time, 0644 );
    }
    catch {
        my $err  = $_;
        my $user = $Cpanel::user || Cpanel::PwCache::getusername();
        Cpanel::Debug::log_info("Could not write cachebuster file “$cache_id_file” for user “$user”: $err\n");
    };

    # should only happen if overquota
    return ( stat($cache_id_file) )[9] || $cache_id_time;
}

sub _get_cache_id_file {
    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir();

    return "$homedir/etc/cacheid";
}

1;
