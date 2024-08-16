package Cpanel::Config::Httpd::IpPort;

# cpanel - Cpanel/Config/Httpd/IpPort.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::Config::Httpd::IpPort - Fetch the IP and Port used by Apache

=head1 SYNOPSIS

    my $main_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    my $ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_port();

    my $ip_main_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_ip_and_port();

    my $ip_ssl_port = Cpanel::Config::Httpd::IpPort::get_ssl_httpd_ip_and_port();



=head1 DESCRIPTION

Returns the IP and Ports that Apache is configured to listen on.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Config::LoadCpConf ();
use Cpanel::IP::Parse          ();

=head2 get_main_httpd_port()

Return the port that Apache is listening on for
non-SSL requests (usually 80)

=cut

my $_get_main_httpd_port;

sub get_main_httpd_port {
    return $_get_main_httpd_port ||= _fetch_http_port( 'cpconfkey' => 'apache_port', 'default_port' => 80 );
}

=head2 get_ssl_httpd_port()

Return the port that Apache is listening on for
SSL requests (usually 443)

=cut

my $_get_ssl_httpd_port;

sub get_ssl_httpd_port {
    return $_get_ssl_httpd_port ||= _fetch_http_port( 'cpconfkey' => 'apache_ssl_port', 'default_port' => 443 );
}

=head2 get_main_httpd_ip_and_port()

Return the IP and port that Apache is listening on for
non-SSL requests (usually 0.0.0.0:80)

=cut

sub get_main_httpd_ip_and_port {
    return _fetch_http_ip_and_port( 'cpconfkey' => 'apache_port', 'default_port' => 80 );
}

=head2 get_ssl_httpd_ip_and_port()

Return the IP and port that Apache is listening on for
SSL requests (usually 0.0.0.0:443)

=cut

sub get_ssl_httpd_ip_and_port {
    return _fetch_http_ip_and_port( 'cpconfkey' => 'apache_ssl_port', 'default_port' => 443 );
}

sub _fetch_http_ip_and_port {
    my %OPTS      = @_;
    my $cpconf    = Cpanel::Config::LoadCpConf::loadcpconf_not_copy();          # safe since we never modify cpconf
    my $main_port = $cpconf->{ $OPTS{'cpconfkey'} } || $OPTS{'default_port'};
    if ( $main_port !~ tr/0-9//c ) {                                            # !~ tr/0-9//c  means does not contain any chars outside of 0-9
        $main_port = "0.0.0.0:$main_port";
    }

    return $main_port;
}

sub _fetch_http_port {
    my %OPTS        = @_;
    my $ip_and_port = _fetch_http_ip_and_port(%OPTS);

    my $port = ( Cpanel::IP::Parse::parse($ip_and_port) )[2];

    return ( $port && $port !~ tr/0-9//c ) ? $port : $OPTS{'default_port'};    # !~ tr/0-9//c  means does not contain any chars outside of 0-9
}

sub clear_cache {
    undef $_get_main_httpd_port;
    undef $_get_ssl_httpd_port;
    return;
}

1;
