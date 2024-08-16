package Cpanel::PHPFPM::Constants;

# cpanel - Cpanel/PHPFPM/Constants.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $system_yaml_dir           = "/var/cpanel/ApachePHPFPM";
our $system_yaml               = "system.yaml";
our $system_pool_defaults_yaml = "system_pool_defaults.yaml";
our $php_conf_path             = '/etc/cpanel/ea4/php.conf';
our $apache_include_path       = qq{/etc/apache2/conf.d/userdata/std};

our $opt_cpanel = '/opt/cpanel';    # use for testing.

our $template_dir = "/usr/local/cpanel/shared/templates";

our $system_conf_tmpl      = "system-php-fpm-conf.tmpl";
our $system_pool_conf_tmpl = "system-php-fpm-pool-conf.tmpl";

our $touch_file = '/default_accounts_to_fpm';

our $delay_for_rebuild = 10;

our $convert_all_pid_file = '/var/cpanel/ea_php_fpm_convert_all_in_progress';

1;
