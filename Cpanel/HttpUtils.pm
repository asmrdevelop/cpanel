package Cpanel::HttpUtils;

# cpanel - Cpanel/HttpUtils.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin             ();
use Cpanel::ConfigFiles::Apache  ();
use Cpanel::HttpUtils::ApRestart ();
use Cpanel::HttpUtils::Conf      ();
use Cpanel::HttpUtils::Htaccess  ();
use Cpanel::HttpUtils::Ip        ();
use Cpanel::HttpUtils::Version   ();

our $VERSION = '1.8';

*get_apache_short_version       = *Cpanel::HttpUtils::Version::get_current_apache_version_key;
*getrewriteinfo                 = *Cpanel::HttpUtils::Htaccess::getrewriteinfo;
*getredirects                   = *Cpanel::HttpUtils::Htaccess::getredirects;
*setupredirection               = *Cpanel::HttpUtils::Htaccess::setupredirection;
*disableredirection             = *Cpanel::HttpUtils::Htaccess::disableredirection;
*redirect_type                  = *Cpanel::HttpUtils::Htaccess::redirect_type;
*test_and_install_htaccess      = *Cpanel::HttpUtils::Htaccess::test_and_install_htaccess;
*get_httpd_version              = *Cpanel::HttpUtils::Version::get_httpd_version;
*find_httpd                     = *Cpanel::HttpUtils::Version::find_httpd;
*get_current_apache_version_key = *Cpanel::HttpUtils::Version::get_current_apache_version_key;
*getipfromdomain                = *Cpanel::HttpUtils::Ip::getipfromdomain;
*fetchdirprotectconf            = *Cpanel::HttpUtils::Conf::fetchdirprotectconf;
*fetchphpopendirconf            = *Cpanel::HttpUtils::Conf::fetchphpopendirconf;
*safeaprestart                  = *Cpanel::HttpUtils::ApRestart::safeaprestart;
*bgsafeaprestart                = *Cpanel::HttpUtils::ApRestart::bgsafeaprestart;
*clear_semaphores               = *Cpanel::HttpUtils::ApRestart::clear_semaphores;
*_check_ap_restart              = *Cpanel::HttpUtils::ApRestart::_check_ap_restart;
*httpd_is_running               = *Cpanel::HttpUtils::ApRestart::httpd_is_running;

sub api2_getdirindices {
    my @RSD;
    my $apacheconf = Cpanel::ConfigFiles::Apache->new();
    foreach my $index ( @{ Cpanel::AdminBin::adminfetch( 'apache', $apacheconf->file_conf(), 'DIRINDEX', 'storable', '0' ) } ) {
        push @RSD, { 'index' => $index };
    }
    return @RSD;
}

our %API = (
    'getdirindices' => { allow_demo => 1 },
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}
1;
