package Cpanel::Template::Plugin::EasyApache;

# cpanel - Cpanel/Template/Plugin/EasyApache.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';
use Cpanel::Config::Httpd::EA4 ();

my $_get_ea_version;

sub reset_cache {
    $_get_ea_version = undef;
    return;
}

sub get_ea_version {
    return ( $_get_ea_version ||= ( Cpanel::Config::Httpd::EA4::is_ea4() ? 4 : 0 ) );
}

1;

__END__
