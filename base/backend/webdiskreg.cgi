#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/webdiskreg.cgi             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel::Encoder::Tiny ();
use Cpanel::Encoder::URI  ();
use Cpanel::Locale        ();
use Cpanel::Logger        ();

my $WINDOWS_DEFAULT_MAX_SIZE_MB = 47;            # 0x02FAF080 or 50000000 B
my $CPANEL_DEFAULT_MAX_SIZE     = 2147483647;    # 2 GB - 1 byte
my $CPANEL_DEFAULT_MAX_SIZE_MB  = 2048;
my $DWORD_MAX_UNSIGNED_INT_MB   = 4095;
my $DWORD_MAX_UNSIGNED_INT      = 4294967295;    # max value the windows registry will accept for this key

my ($maxFileSize) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );

my $locale = Cpanel::Locale->get_handle();

if ( !$maxFileSize || ( $maxFileSize = int($maxFileSize) ) < $WINDOWS_DEFAULT_MAX_SIZE_MB ) {
    $maxFileSize = $CPANEL_DEFAULT_MAX_SIZE;
}
elsif ( $maxFileSize >= $DWORD_MAX_UNSIGNED_INT_MB ) {
    $maxFileSize = $DWORD_MAX_UNSIGNED_INT;
}
else {
    $maxFileSize *= 1048576;    # MB to B
}

$maxFileSize = sprintf( "%x", $maxFileSize );

my $fileName = Cpanel::Encoder::URI::uri_encode_str('WebClientFileSizeLimit.reg');

if ( open( my $wdisk_fh, '<', '/usr/local/cpanel/base/backend/WebClientFileSizeLimit.reg' ) ) {
    print <<EOM;
Content-Type: application/download; name="$fileName";
Content-Disposition: attachment; filename="$fileName";

EOM
    while ( readline($wdisk_fh) ) {
        s/__MAX_FILE_SIZE__/$maxFileSize/g;
        print;
    }
    close($wdisk_fh);
}
else {
    my $logger;
    $logger ||= Cpanel::Logger->new();
    $logger->warn('Unable to locate WebClientFileSizeLimit.reg.');
    my $fileNotFoundTitle = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable To Locate File') );
    my $fileNotFoundBody  = Cpanel::Encoder::Tiny::safe_html_encode_str( $locale->maketext('Unable to locate file.') );
    print "Content-type: text/html\r\n\r\n<html><head><title>$fileNotFoundTitle</title></head><body>$fileNotFoundBody</body></html>";
    exit;
}
