package Cpanel::HttpUtils::Vhosts::Primary::Extract;

# cpanel - Cpanel/HttpUtils/Vhosts/Primary/Extract.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::ConfigFiles::Apache 'apache_paths_facade';    # see POD for import specifics
use Cpanel::ApacheConf::Parser::Regex ();
use Cpanel::LoadModule                ();
use Cpanel::Config::Httpd::IpPort     ();
use Cpanel::HttpUtils::Vhosts::Regex  ();
use Cpanel::IP::Parse                 ();
use Cpanel::WildcardDomain            ();

#See note in scripts/primary_virtual_host_migration.
sub extract_primary_vhosts_from_apache_conf {
    my ($httpdconf_text_sr) = @_;

    if ( !$httpdconf_text_sr || !ref $httpdconf_text_sr ) {
        open( my $rfh, '<', apache_paths_facade->file_conf() ) or do {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
            my $locale = Cpanel::Locale->get_handle();
            return ( 0, $locale->maketext( 'The system failed to read [asis,Apache]’s configuration file because of an error: [_1]', $! ) );
        };

        my $httpd_conf_text = do { local $/; <$rfh> };
        close $rfh;
        $httpdconf_text_sr = \$httpd_conf_text;
    }

    my %primary_vhosts_hash;

    my $vhost_regexp              = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_Content_Capture();
    my $servername_capture_regexp = Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerName_Capture();
    my $ip_capture_regexp         = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_IP_Capture();

    my $default_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    # If service (formerly proxy) subdomains is enabled we don't want to map ips that no other user owns to the servername.
    # So we'll just end when we get to the service (formerly proxy) subdomains virtualhost
    my $proxy_subdomains_start_pos;
    if ( ${$httpdconf_text_sr} =~ m/\n[ \t]*# CPANEL\/WHM\/WEBMAIL(\/WEBDISK)?(?:\/AUTOCONFIG)? PROXY SUBDOMAINS/ ) {
        $proxy_subdomains_start_pos = $-[0];    #This is really the position of \n
    }

  VHOST:
    while ( $$httpdconf_text_sr =~ m{$vhost_regexp}g ) {
        my ( $vhost_open, $vhost_content, $vhost_open_start_pos ) = ( $1, $2, $+[0] );

        # We don't want to pick up the service (formerly proxy) subdomains virtualhost ips
        last if $proxy_subdomains_start_pos && $proxy_subdomains_start_pos < $vhost_open_start_pos;

        $vhost_open =~ m{$ip_capture_regexp};
        my $ips_str = $1;
        $ips_str =~ s{\s+\z}{};
        my @ips = split m{\s+}, $ips_str;

        my $servername;
        for my $ip_port (@ips) {
            next if $ip_port eq '*';
            my ( $version, $ip, $port ) = Cpanel::IP::Parse::parse( $ip_port, undef, $Cpanel::IP::Parse::BRACKET_IPV6 );

            $port ||= $default_port;

            if ( !exists $primary_vhosts_hash{"$ip:$port"} ) {
                if ( !defined $servername ) {
                    next VHOST if $vhost_content !~ $servername_capture_regexp;
                    $servername = $1;
                    $servername =~ tr{A-Z}{a-z};

                    $servername = Cpanel::WildcardDomain::decode_wildcard_domain($servername);
                }
                $primary_vhosts_hash{"$ip:$port"} = $servername;
            }
        }
    }

    return ( 1, \%primary_vhosts_hash );
}

1;
