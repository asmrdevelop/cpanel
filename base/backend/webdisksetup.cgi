#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/webdisksetup.cgi           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Archive::Zip;
use Cpanel::Encoder::URI ();

my ( $domain, $ssl, $ver, $port ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
$ssl = int($ssl);
my $secure    = $ssl ? 'Secure ' : '';
my $securetxt = $ssl ? 'Secure ' : '';
$port = $port ? $port : $ssl ? '2078' : '2077';
my $webdav_uri = ( $ssl ? 'https://' : 'http://' ) . $domain . ':' . $port;

print <<EOM;
Content-Type: application/zip; name="${domain} ${secure}WebDisk.app.zip"; x-mac-auto-archive=yes
Content-Disposition: attachment; filename="${domain} ${secure}WebDisk.app.zip";

EOM

my $zip = Archive::Zip->new();

if ( $ver eq '10.5' ) {
    $zip->read('/usr/local/cpanel/obj/WebDisk_Setup_Leopard.app.zip');

    # http://www.cocoabuilder.com/archive/xcode/301731-resourcerules-plist-how-do-exclude-specific-files-from-codesigning.html
    # https://developer.apple.com/library/mac/technotes/tn2206/_index.html
    # It is thus no longer possible to exclude parts of a bundle from the signature. Bundles should be treated as read-only once they have been signed.
    # We can't sign them on the server since that will exponse our key.  We are stuck with the below hack.
    $zip->addString( $ssl . "\t" . $domain . "\t" . $webdav_uri, 'WebDisk_Setup_Leopard.app/Contents/Resources/webdav.lproj/locversion.plist' );
}
else {
    $zip->read('/usr/local/cpanel/obj/Web_Disk.app.zip');
    $zip->addString( $domain,                                    'Web_Disk_Setup_2.0.app/Contents/Resources/domain.txt' );
    $zip->addString( $ssl,                                       'Web_Disk_Setup_2.0.app/Contents/Resources/usessl.txt' );
    $zip->addString( $ssl . "\t" . $domain . "\t" . $webdav_uri, 'Web_Disk_Setup_2.0.app/Contents/Resources/webdav.txt' );
}

foreach my $member ( $zip->members() ) {
    my $memberName = $member->fileName();

    my $newname = $memberName;
    $newname =~ s/Web\_?Disk[^\/]+\//${domain} ${securetxt}WebDisk.app\//g;
    $member->fileName($newname);
}

$zip->writeToFileHandle( \*STDOUT );

__END__
How to update the bundle:

Right click, Show Package contents => Contents => Resources => Scripts

Open apple script

File Export to WebDisk_Setup_Leopard
 - Do not codesign
 - Save as application
 - Show startup screen : yes
 - Stay open : no
 - Run-only : no

Right click on new script, Show Package contents => Contents

Now enter Resources

Replace applet.icns with the one from the old package (find it the same was as above)

sudo codesign -s "Developer ID Application: cPanel, L.L.C." WebDisk_Setup_Leopard.app

Drag script.app to email

Email it to yourself (this ensures mac does the compression so it can reverse it)

Find the email in your sent file.

Use View -> Message -> Raw Source

Extract the base64 from view source to a file a called x.b64

perl -MCpanel::LoadFile -MMIME::Base64 -e 'my $x = Cpanel::LoadFile::loadfile("x.b64"); $x =~ s/\n//g; print MIME::Base64::decode_base64("$x");' > g
mv g obj/WebDisk_Setup_Leopard.app.zip

** NOTE to accommodate 10.10+ all config files must be named **
Contents/Resources/webdav.lproj/locversion.plist

Test it
