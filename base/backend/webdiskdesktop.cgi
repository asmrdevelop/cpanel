#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/webdiskdesktop.cgi         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Encoder::URI           ();
use Cpanel::Encoder::Tiny          ();
use Cpanel::Locale                 ();
use Cpanel::Logger                 ();
use Cpanel::Validate::Domain::Tiny ();

my $locale = Cpanel::Locale->get_handle();
my $logger;
my ( $domain, $ssl, $port, $app ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );

if ( !$domain || !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Invalid domain name passed.');
    my $invalidDomainTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Invalid Domain') );
    my $invalidDomainBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('An invalid domain name was passed.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$invalidDomainTitle</title></head><body>$invalidDomainBody</body></html>";
    exit;
}

$ssl  = int($ssl);
$port = $port ? int $port : $ssl ? '2078' : '2077';

my $txtsecure = $ssl ? $locale->maketext('Secure') . ' ' : '';
my $secure    = Cpanel::Encoder::URI::uri_encode_str($txtsecure);
my $usecure   = $txtsecure;
$usecure =~ s/ /_/g;
my $sslc     = $ssl ? 's' : '';
my $icon     = ( $app eq 'nautilus' ? 'folder' : 'konqueror' );
my $protocol = ( $app eq 'nautilus' ? 'dav'    : 'webdav' ) . $sslc . '://';

# Since this is a filename, we want the domain at the beginning and the file extension at the end. Thus, we only localize the label in between:
my $fileName = "$domain " . ( $ssl ? $locale->maketext('Secure') : '' ) . 'WebDisk.desktop';

# So many browers, so much brokeness, see http://greenbytes.de/tech/tc2231/
$fileName = Cpanel::Encoder::URI::uri_encode_str($fileName);

print <<EOM;
Content-Type: application/download; name="$fileName";
Content-Disposition: attachment; filename="$fileName";

EOM

if ( open( my $wdisk_fh, '<', '/usr/local/cpanel/base/backend/webdisk.desktop' ) ) {
    while ( readline($wdisk_fh) ) {
        s/\%protocol\%/$protocol/g;
        s/\%domain\%/$domain/g;
        s/\%icon\%/$icon/g;
        s/\%url\%//g;
        s/\%port\%/$port/g;
        s/\%txtsecure\%/$txtsecure/g;
        s/\%secure\%/$secure/g;
        s/\%usecure\%/$usecure/g;
        s/\%sslc\%/$sslc/g;
        print;
    }
    close($wdisk_fh);
}
else {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Unable to locate webdisk.desktop');
    my $fileNotFoundTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable To Locate File') );
    my $fileNotFoundBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable to locate file.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$fileNotFoundTitle</title></head><body>$fileNotFoundBody</body></html>";
    exit;
}
