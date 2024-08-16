package Cpanel::HttpUtils::Vhosts::Regex;

# cpanel - Cpanel/HttpUtils/Vhosts/Regex.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Httpd::IpPort ();

my $_virtualhost_content_capture_regex;
my $_virtualhost_ip_capture_regex;

# This regular expression should also use the g option. Since we can't return g on qr
# you'll need to use it like this:
#   my $virtualhost_content_regex = Cpanel::HttpUtils::Vhosts::Regex::VirtualHost_Content_Capture();
#   while( $httpdconf_text =~ m/$virtualhost_content_regex/g )
sub VirtualHost_Content_Capture {
    return ( $_virtualhost_content_capture_regex ||= qr/(\n\<virtualhost[^\>]+\>)(.*?)(<\/virtualhost\>)/si );
}

sub VirtualHost_IP_Capture {
    return ( $_virtualhost_ip_capture_regex ||= qr/<virtualhost[ \t]+([^\r\n\>]+)/im );
}

sub Generate_VirtualHost_Port_Match_Regex {
    my ($port) = @_;
    my $default_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    if ( !$port || $port eq $default_port ) {
        return qr{
            (?::[0-9a-fA-F]+\]|\.[0-9]+)    # IPv6 aware
            (?::\Q$default_port\E)?
            [ \t>]
        }x;
    }
    else {
        return qr{
            :
            \Q$port\E
            [ \t>]
        }x;    #IPv6 aware
    }
}

#TODO: Should we detect IPv6 addresses and enclose them in [] here?
sub Generate_VirtualHost_IP_Port_Match_Regex {
    my ( $ip, $port ) = @_;
    my $default_port = Cpanel::Config::Httpd::IpPort::get_main_httpd_port();

    if ( !$port || $port eq $default_port ) {
        return qr{[ \t]\Q$ip\E(?::\Q$default_port\E)?[ \t>]};    # IPv6 aware
    }
    else {
        return qr{[ \t]\Q$ip\E:\Q$port\E[ \t>]};                 #IPv6 aware
    }
}

1;
