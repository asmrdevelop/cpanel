package Cpanel::Config::Httpd;

# cpanel - Cpanel/Config/Httpd.pm                    Copyright 2022 cPanel L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::EA4    ();
use Cpanel::Config::Httpd::IpPort ();
use Cpanel::Config::Httpd::Paths  ();
use Cpanel::Config::Httpd::Vendor ();
use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics

{
    no warnings 'once';
    *is_ea4                     = *Cpanel::Config::Httpd::EA4::is_ea4;                          # required for EA4. See CPANEL-13528
    *is_ea4_cached              = *Cpanel::Config::Httpd::EA4::is_ea4;                          # required for EA4. See CPANEL-13528
    *httpd_binary_location      = sub { apache_paths_facade->bin_httpd() };
    *get_main_httpd_port        = *Cpanel::Config::Httpd::IpPort::get_main_httpd_port;
    *get_ssl_httpd_port         = *Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port;
    *get_main_httpd_ip_and_port = *Cpanel::Config::Httpd::IpPort::get_main_httpd_ip_and_port;
    *get_ssl_httpd_ip_and_port  = *Cpanel::Config::Httpd::IpPort::get_ssl_httpd_ip_and_port;
    *default_httpd_dir          = *Cpanel::Config::Httpd::Paths::default_httpd_dir;
    *default_cpanel_dir         = *Cpanel::Config::Httpd::Paths::default_cpanel_dir;
    *default_product_dir        = *Cpanel::Config::Httpd::Paths::default_product_dir;
    *default_run_dir            = *Cpanel::Config::Httpd::Paths::default_run_dir;
    *suexec_binary_location     = *Cpanel::Config::Httpd::Paths::suexec_binary_location;
    *splitlogs_binary_location  = *Cpanel::Config::Httpd::Paths::splitlogs_binary_location;
    *httpd_vendor_info          = *Cpanel::Config::Httpd::Vendor::httpd_vendor_info;
}

1;
