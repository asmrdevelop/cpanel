#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/webdiskvbs-vista.cgi       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Encoder::Tiny          ();
use Cpanel::Encoder::URI           ();
use Cpanel::Encoder::VBScript      ();
use Cpanel::Locale                 ();
use Cpanel::Logger                 ();
use Cpanel::Validate::Domain::Tiny ();

my ( $domain, $ssl, $port ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
my $logger;

my $locale = Cpanel::Locale->get_handle();

if ( !$domain || !Cpanel::Validate::Domain::Tiny::validdomainname($domain) ) {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Invalid domain name passed.');
    my $invalidDomainTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Invalid Domain') );
    my $invalidDomainBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('An invalid domain name was passed.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$invalidDomainTitle</title></head><body>$invalidDomainBody</body></html>";
    exit;
}

$ssl  = int($ssl);
$port = int($port);
$port = $port > 0 ? $port : $ssl ? '2078' : '2077';

my $sslPortText = $ssl ? "SSL@" . $port : $port;
my $domainPort  = "$domain@" . $sslPortText;
my $uri         = "\\\\$domainPort\\DavWWWRoot";

# Since this is a filename, we want the domain at the beginning and the file extension at the end. Thus, we only localize the label in between:
my $fileName = "$domain " . ( $ssl ? $locale->maketext('Secure WebDisk') : $locale->maketext('WebDisk') ) . '.vbs';

my $vbFileName = Cpanel::Encoder::VBScript::encode_vbscript_str($fileName);
$fileName = Cpanel::Encoder::URI::uri_encode_str($fileName);

# Since this is a filename, we want the domain at the beginning and the file extension at the end. Thus, we only localize the label in between:
my $shortCut = "$domain " . ( $ssl ? $locale->maketext('Secure WebDisk') : $locale->maketext('WebDisk') );
$shortCut = Cpanel::Encoder::VBScript::encode_vbscript_str($shortCut);

my $webClientError = Cpanel::Encoder::VBScript::encode_vbscript_str( $locale->maketext( 'Could not find “[_1]” service.', 'WebClient' ) );
my $webdiskMessage = Cpanel::Encoder::VBScript::encode_vbscript_str( $locale->maketext('Connecting to your WebDisk now; this may take a minute.') );
my $webdiskTitle   = Cpanel::Encoder::VBScript::encode_vbscript_str( $locale->maketext('Connecting to Webdisk') );

if ( open( my $wdisk_fh, '<', '/usr/local/cpanel/base/backend/webdisk-vista.vbs' ) ) {
    print <<EOM;
Content-Type: application/download; name="$fileName";
Content-Disposition: attachment; filename="$fileName";

EOM
    while ( readline($wdisk_fh) ) {
        s/\%domain\%/$domain/g;
        s/\%domainPort\%/$domainPort/g;
        s/\%uri\%/$uri/g;
        s/\%fileName\%/$vbFileName/g;
        s/\%shortCut\%/$shortCut/g;
        s/\%webClientError\%/$webClientError/g;
        s/\%webdiskMessage\%/$webdiskMessage/g;
        s/\%webdiskTitle\%/$webdiskTitle/g;
        print;
    }
    close($wdisk_fh);
}
else {
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Unable to locate webdisk-vista.vbs.');
    my $fileNotFoundTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable To Locate File') );
    my $fileNotFoundBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable to locate file.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$fileNotFoundTitle</title></head><body>$fileNotFoundBody</body></html>";
    exit;
}
