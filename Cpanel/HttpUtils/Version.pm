package Cpanel::HttpUtils::Version;

# cpanel - Cpanel/HttpUtils/Version.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::GlobalCache ();

our $VERSION = 1.1;

*get_apache_short_version = *get_current_apache_version_key;

# Used in a comparison operation
*get_apache_decimal_version = *get_current_apache_uri_version;

sub get_httpd_version {
    my $bin = shift || find_httpd();
    return if !$bin || !-x $bin;

    if ( Cpanel::GlobalCache::cachedcommand( 'cpanel', $bin, '-v' ) =~ m{Apache/(\d+\.\d+\.\d+)} ) {
        return $1;
    }
    return;
}

sub find_httpd {
    my $dir       = default_httpd_dir();
    my $httpd_bin = $dir eq apache_paths_facade->dir_base() ? apache_paths_facade->bin_httpd() : "$dir/bin/httpd";
    my $httpd     = -e $httpd_bin                           ? $httpd_bin                       : '';
    return $httpd;
}

my $_get_current_apache_version_key;

sub get_current_apache_version_key {    ## no critic qw(Subroutines::RequireArgUnpacking)
    return $_get_current_apache_version_key if defined $_get_current_apache_version_key;
    my $vstring = get_httpd_version(@_);
    return if !$vstring;
    my $short_ver =
        $vstring =~ m{1[.]3[.]} ? 1
      : $vstring =~ m{2[.]0[.]} ? 2
      : $vstring =~ m{2[.]2[.]} ? '2_2'
      : $vstring =~ m{2[.]4[.]} ? '2_4'
      :                           undef;

    return $_get_current_apache_version_key = $short_ver if defined $short_ver;
    return;
}

sub get_current_apache_uri_version {    ## no critic qw(Subroutines::RequireArgUnpacking)
    my $apache_version_key = get_current_apache_version_key(@_);
    return if !$apache_version_key;

    my $uri_version =
        $apache_version_key eq '1'   ? '1.3'
      : $apache_version_key eq '2'   ? '2.0'
      : $apache_version_key eq '2_2' ? '2.2'
      : $apache_version_key eq '2_4' ? '2.4'
      :                                undef;

    return $uri_version if defined $uri_version;
    return;
}

{
    my $HTTPD_BASE_DIR;    # no access outside of the function below

    sub default_httpd_dir {
        $HTTPD_BASE_DIR = shift if @_;

        if ( !defined $HTTPD_BASE_DIR ) {    # default value
            $HTTPD_BASE_DIR = apache_paths_facade->dir_base();
        }

        return $HTTPD_BASE_DIR;
    }
}

sub clear_cache {
    undef $_get_current_apache_version_key;
    return;
}
1;
