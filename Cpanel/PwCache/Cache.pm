package Cpanel::PwCache::Cache;

# cpanel - Cpanel/PwCache/Cache.pm                   Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

my %_cache;
my %_homedir_cache;
use constant get_cache         => \%_cache;
use constant get_homedir_cache => \%_homedir_cache;

our $pwcache_inited = 0;
my $PWCACHE_IS_SAFE = 1;

sub clear {    # clear all
    %_cache         = ();
    %_homedir_cache = ();
    $pwcache_inited = 0;
    return;
}

sub remove_key {
    my ($pwkey) = @_;
    return delete $_cache{$pwkey};
}

sub replace {
    my $h = shift;
    %_cache = %$h if ref $h eq 'HASH';
    return;
}

# set and get
sub is_safe {
    $PWCACHE_IS_SAFE = $_[0] if defined $_[0];
    return $PWCACHE_IS_SAFE;
}

sub pwmksafecache {
    return if $PWCACHE_IS_SAFE;
    $_cache{$_}{'contents'}->[1] = 'x' for keys %_cache;
    $PWCACHE_IS_SAFE = 1;
    return;
}

1;
