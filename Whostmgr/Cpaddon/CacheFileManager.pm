#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - Whostmgr/Cpaddon/CacheFileManager.pm     Copyright 2022 cPanel, L.L.C.
#                                                            All rights Reserved.
# copyright@cpanel.net                                          http://cpanel.net
# This code is subject to the cPanel license.  Unauthorized copying is prohibited

package Whostmgr::Cpaddon::CacheFileManager;

use strict;
use warnings;

use parent qw( Cpanel::CacheFile );

my $CACHE_FILE_PATH  = '/var/cpanel/available_addons_packages.cache';
my $CACHE_FILE_PERMS = 0644;                                            # root rw and everyone else can read
our $CACHE_TTL = 14400;                                                 # seconds, i.e., 4 hours

=head1 NAME

Whostmgr::Cpaddon::CacheFileManager

=head1 DESCRIPTION

Cache file policy for the cpaddons packages fetched from YUM.

=cut

#----------------
# CACHE POLICY
#----------------
sub _PATH { return $CACHE_FILE_PATH; }

sub _TTL { return $CACHE_TTL; }

sub load_expired {
    local $CACHE_TTL = 86400 * 365 * 20;
    return __PACKAGE__->load();
}

sub _MODE { return $CACHE_FILE_PERMS; }

1;
