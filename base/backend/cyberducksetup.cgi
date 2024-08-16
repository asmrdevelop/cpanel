#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/cyberducksetup.cgi         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::SSH          ();
use Cpanel::Encoder::URI ();

my $sshport = Cpanel::SSH::_getport();
my $proto;
my ( $domain, $host, $user, $ssl ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
$ssl = int($ssl);
my $secure    = $ssl ? 'Secure%20' : '';
my $securetxt = $ssl ? 'Secure '   : '';
my $port;
if ($ssl) {
    $port  = $sshport;
    $proto = 'sftp';
}
else {
    $port  = 21;
    $proto = 'ftp';
}

print <<"EOM";
Content-Type: application/octet-stream; x-unix-mode=0644; name="${securetxt}$domain.duck"
Content-Disposition: attachment; filename="${securetxt}$domain.duck"

<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
        <dict>
            <key>Hostname</key>
            <string>$host</string>
            <key>Nickname</key>
            <string>$domain $securetxt</string>
            <key>Port</key>
            <string>$port</string>
            <key>Protocol</key>
            <string>$proto</string>
            <key>Username</key>
            <string>$user</string>
        </dict>
</plist>
EOM
