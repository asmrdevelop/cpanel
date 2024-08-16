
# cpanel - Cpanel/Hulk/Cache/IpLists.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Hulk::Cache::IpLists;

use strict;
use warnings;

use Cpanel::Config::Hulk ();
use parent 'Cpanel::SmallConstCache';

sub new {
    my ( $class, @opts_kv ) = @_;

    my $dir = Cpanel::Config::Hulk->can('get_cache_dir');
    $dir &&= $dir->();

    # In case get_cache_dir() isn’t defined, which can happen if, e.g.,
    # this runs from queueprocd after new modules are installed but
    # before queueprocd is restarted to use the new modules.
    $dir ||= $Cpanel::Config::Hulk::cache_dir;

    die 'Can’t determine cPHulk cache directory!' if !defined $dir;

    return $class->SUPER::new( 'dir' => $dir, @opts_kv );
}

1;
