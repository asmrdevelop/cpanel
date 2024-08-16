package Cpanel::Locale::Utils::Paths;

# cpanel - Cpanel/Locale/Utils/Paths.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use constant {
    get_legacy_lang_cache_root => '/var/cpanel/lang.cache',
    get_i_locales_config_path  => '/var/cpanel/i_locales',
    get_custom_whitelist_path  => '/var/cpanel/maketext_whitelist'
};

sub get_locale_database_root   { return '/var/cpanel/locale' }
sub get_locale_yaml_root       { return '/usr/local/cpanel/locale' }
sub get_legacy_lang_root       { return '/usr/local/cpanel/lang' }
sub get_locale_yaml_local_root { return '/var/cpanel/locale.local' }

1;
