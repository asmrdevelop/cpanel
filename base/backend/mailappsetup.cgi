#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/mailappsetup.cgi           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Encoder::URI ();
use Archive::Zip         ();

my $useroot = 0;
my ( $acct, $host, $smtpport, $usessl, $hasmaildir, $ver, $archive_config ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
my ( $user, $domain ) = split( /\@/, $acct );
if ( !$domain ) {
    require Cpanel::Config::LoadCpUserFile;
    my $cpuserconf_ref = Cpanel::Config::LoadCpUserFile::loadcpuserfile( $ENV{'REMOTE_USER'} );
    $domain  = $cpuserconf_ref->{'DOMAIN'};
    $useroot = 1;
}

## force a 0 or 1
$archive_config = !!$archive_config;

my $displayacct = $archive_config ? $domain : $acct;
my $safeacct    = $displayacct;
$safeacct =~ s/[^A-Za-z0-9\.\@]/_/g;
my $displayname = $archive_config ? 'Email Archive Setup' : 'Email Setup';

my $ssl       = int($usessl);
my $secure    = $ssl ? 'Secure ' : '';
my $securetxt = $ssl ? 'Secure ' : '';
$hasmaildir = int $hasmaildir;

print <<EOM;
Content-Type: application/zip; name="${safeacct} ${secure}$displayname.app.zip"; x-mac-auto-archive=yes
Content-Disposition: attachment; filename="${safeacct} ${secure}$displayname.app.zip"

EOM

my $zip = Archive::Zip->new();

if ( $ver eq '10.7' ) {

    # http://www.cocoabuilder.com/archive/xcode/301731-resourcerules-plist-how-do-exclude-specific-files-from-codesigning.html
    # https://developer.apple.com/library/mac/technotes/tn2206/_index.html
    # It is thus no longer possible to exclude parts of a bundle from the signature. Bundles should be treated as read-only once they have been signed.
    # We can't sign them on the server since that will exponse our key.  We are stuck with the below hack.
    $zip->addString( $useroot . "\t" . $user . "\t" . $domain . "\t" . $host . "\t" . $usessl . "\t" . $smtpport, 'cPanel_Email_Setup_5.2.app/Contents/Resources/mailappsetup.lproj/locversion.plist' );
    $zip->read("/usr/local/cpanel/obj/Email_Setup_Lion.app.zip");
}
else {
    $zip->read("/usr/local/cpanel/obj/Email_Setup.app.zip");
    $zip->addString( $useroot,    'cPanel_Email_Setup_4.3.app/Contents/Resources/useroot.txt' );
    $zip->addString( $domain,     'cPanel_Email_Setup_4.3.app/Contents/Resources/domain.txt' );
    $zip->addString( $host,       'cPanel_Email_Setup_4.3.app/Contents/Resources/host.txt' );
    $zip->addString( $user,       'cPanel_Email_Setup_4.3.app/Contents/Resources/user.txt' );
    $zip->addString( $smtpport,   'cPanel_Email_Setup_4.3.app/Contents/Resources/smtpport.txt' );
    $zip->addString( $usessl,     'cPanel_Email_Setup_4.3.app/Contents/Resources/usessl.txt' );
    $zip->addString( $hasmaildir, 'cPanel_Email_Setup_4.3.app/Contents/Resources/maildir.txt' );
}

#$zip->writeToFileNamed('Email_Setup.app.zip');

foreach my $member ( $zip->members() ) {
    my $memberName = $member->fileName();

    my $newname = $memberName;
    if ( $ver eq '10.7' ) {
        $newname =~ s/cPanel_Email_Setup_5...app/${safeacct} ${securetxt}$displayname.app/g;
    }
    else {
        $newname =~ s/cPanel_Email_Setup_4.3.app/${safeacct} ${securetxt}$displayname.app/g;
    }
    $member->fileName($newname);
}

my ( $fh, $name );

write_file($zip);
exit;

sub _remove_file {
    unlink $name if $name;
}

sub write_file {
    my $zip = shift;

    $SIG{'INT'} = $SIG{'HUP'} = \&_remove_file;

    ( $fh, $name ) = Archive::Zip::tempFile();
    $zip->writeToFileHandle($fh);
    seek( $fh, 0, 0 );
    local ($/);
    print readline($fh);
    close($fh);
    _remove_file();
}

__END__
How to update the bundle:

Right click, Show Package contents => Contents => Resources => Scripts

Open apple script

File Export to cPanel_Email_Setup_5.2
 - Do not codesign
 - Save as application
 - Show startup screen : yes
 - Stay open : no
 - Run-only : no

Right click on new script, Show Package contents => Contents

Now enter Resources

Replace applet.icns with the one from the old package (find it the same was as above)

sudo codesign -s "Developer ID Application: cPanel, L.L.C." cPanel_Email_Setup_5.2.app

Drag script.app to email

Email it to yourself (this ensures mac does the compression so it can reverse it)

Find the email in your sent file.

Use View -> Message -> Raw Source

Extract the base64 from view source to a file a called x.b64

perl -MCpanel::LoadFile -MMIME::Base64 -e 'my $x = Cpanel::LoadFile::loadfile("x.b64"); $x =~ s/\n//g; print MIME::Base64::decode_base64("$x");' > g
mv g obj/Email_Setup_Lion.app.zip

** NOTE to accommodate 10.10+ all config files must be named **
Contents/Resources/webdav.lproj/locversion.plist

Test it
