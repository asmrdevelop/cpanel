package Cpanel::Config::Nginx;

# cpanel - Cpanel/Config/Nginx.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::Nginx

=head1 SYNOPSIS

    if ( Cpanel::Config::Nginx::is_ea_nginx_installed() ) { ... }

=head1 DESCRIPTION

Nothing outlandish here: This module is just a lightweight way to see
if the current system has the ea-nginx package(s) installed.

=head1 METHODS

=cut

use cPstrict;

use Cpanel::Autodie ();

our $base_nginx_dir        = '/etc/nginx/ea-nginx';
our $nginx_cache_file      = "$base_nginx_dir/cache.json";
our $nginx_standalone_file = "$base_nginx_dir/enable.standalone";

=head2 is_ea_nginx_installed()

Returns 1 or 0 to indicate whether the system identifies as having ea-nginx installed.
Throws an exception if a filesystem error (e.g., EACCES) prevents us from
retrieving this information.

=cut

sub is_ea_nginx_installed {
    return Cpanel::Autodie::exists($nginx_cache_file) ? 1 : 0;
}

=head2 is_ea_nginx_in_standalone_mode()

Returns 1 or 0 to indicate whether the system identifies as having ea-nginx
installed in standalone mode.  Throws an exception if a filesystem error (e.g., EACCES) 
prevents us from retrieving this information.

=cut

sub is_ea_nginx_in_standalone_mode {
    return Cpanel::Autodie::exists($nginx_standalone_file) ? 1 : 0;
}

=head2 get_ea_nginx_std_port()

Returns the std port that ea-nginx is listening on.  Dies if ea-nginx is not installed.
NOTE:  This is hard coded to 80 for now since we do not allow users to configure the port
       that ea-nginx is listening on

=cut

sub get_ea_nginx_std_port {
    die "ea-nginx is not installed on this system\n" unless is_ea_nginx_installed();
    return 80;
}

=head2 get_ea_nginx_ssl_port()

Returns the ssl port that ea-nginx is listening on.  Dies if ea-nginx is not installed.
NOTE:  This is hard coded to 443 for now since we do not allow users to configure the port
       that ea-nginx is listening on

=cut

sub get_ea_nginx_ssl_port {
    die "ea-nginx is not installed on this system\n" unless is_ea_nginx_installed();
    return 443;
}

1;
