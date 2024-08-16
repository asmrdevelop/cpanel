package Cpanel::ProxyUtils;

# cpanel - Cpanel/ProxyUtils.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadCpConf ();

sub proxied {
    my $cpconf = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();
    return 0 unless $cpconf->{'proxysubdomains'};
    return 1 if $ENV{'HTTP_PROXIED'} && $ENV{'HTTP_HOST'} =~ /^(?:webmail|webdisk|cpanel|whm|autodiscover|autoconfig)\./;
    return 0;
}

sub getroothost {
    my $previous_host = $ENV{'HTTP_HOST'};

    # Why are these expanded beyond the standard webmail/cpanel/whm?
    return $previous_host if $previous_host =~ s/^webmaild?\.//;
    return $previous_host if $previous_host =~ s/^webdiskd?\.//;
    return $previous_host if $previous_host =~ s/^cpaneld?\.//;
    return $previous_host if $previous_host =~ s/^(?:whm|whostmgr)d?\.//;
    return $previous_host if $previous_host =~ s/^www\.//;
    return $previous_host;
}

sub proxyaddress {
    my $newapp = shift;

    my $previous_host = getroothost();

    my $new_host;
    if ( $newapp eq 'cpaneld' || $newapp eq 'cpanel' ) {
        $new_host = 'cpanel' . '.' . $previous_host;
    }
    elsif ( $newapp eq 'webmaild' || $newapp eq 'webmail' ) {
        $new_host = 'webmail' . '.' . $previous_host;
    }
    elsif ( $newapp eq 'webdiskd' || $newapp eq 'webdisk' ) {
        $new_host = 'webdisk' . '.' . $previous_host;
    }
    elsif ( $newapp eq 'autoconfig' ) {
        $new_host = 'autoconfig' . '.' . $previous_host;
    }
    elsif ( $newapp eq 'autodiscover' ) {
        $new_host = 'autodiscover' . '.' . $previous_host;
    }

    elsif ( $newapp eq 'whostmgrd' || $newapp eq 'whm' ) {
        $new_host = 'whm' . '.' . $previous_host;
    }
    if ( !$new_host ) {
        $new_host = $ENV{'HTTP_HOST'};
    }

    $Cpanel::CPVAR{'new_proxy_domain'} = $new_host;

    require Cpanel::Config::Httpd::IpPort;
    require Cpanel::Config::Nginx;

    my $has_ea_nginx = Cpanel::Config::Nginx::is_ea_nginx_installed();

    if ( $ENV{'HTTPS'} eq 'on' ) {
        my $ssl_port =
          $has_ea_nginx
          ? Cpanel::Config::Nginx::get_ea_nginx_ssl_port()
          : Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

        if ( $ssl_port eq '443' ) {
            $new_host = 'https://' . $new_host;
        }
        else {
            $new_host = 'https://' . $new_host . ':' . $ssl_port;
        }
    }
    else {
        my $http_port =
          $has_ea_nginx
          ? Cpanel::Config::Nginx::get_ea_nginx_std_port()
          : Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

        if ( $http_port eq '80' ) {
            $new_host = 'http://' . $new_host;
        }
        else {
            $new_host = 'http://' . $new_host . ':' . $http_port;
        }
    }

    $Cpanel::CPVAR{'new_proxy_host'} = $new_host;
    return $new_host;
}

1;
