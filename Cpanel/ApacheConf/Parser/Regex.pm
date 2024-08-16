package Cpanel::ApacheConf::Parser::Regex;

# cpanel - Cpanel/ApacheConf/Parser/Regex.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

my $_virtualhost_servername_capture_regex;
my $_virtualhost_serveralias_capture_regex;

sub VirtualHost_ServerName_Capture {
    return ( $_virtualhost_servername_capture_regex ||= qr/\n[ \t]*servername[ \t]+(?:www\.)?(\S+)/is );
}

# This regular expression should also use the g option. Since we can't return g on qr
# you'll need to use it like this:
#   my $serveralias_regex = Cpanel::ApacheConf::Parser::Regex::VirtualHost_ServerAlias_Capture();
#   if( $virtualhost_content =~ m/$serveralias_regex/g )
sub VirtualHost_ServerAlias_Capture {
    return ( $_virtualhost_serveralias_capture_regex ||= qr/\n[ \t]*serveralias[ \t]+([^\r\n]+)/im );
}

1;
