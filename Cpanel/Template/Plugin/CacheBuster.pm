package Cpanel::Template::Plugin::CacheBuster;

# cpanel - Cpanel/Template/Plugin/CacheBuster.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';

use Cpanel::Themes::CacheBuster ();

*_get_cache_id = *Cpanel::Themes::CacheBuster::get_cache_id;

sub new {
    my ($class) = @_;
    return bless { 'id' => \&_get_cache_id }, $class,;
}

1;
