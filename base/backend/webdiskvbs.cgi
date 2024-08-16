#!/usr/local/cpanel/3rdparty/bin/perl

use Cpanel::Encoder::URI ();

my ( $domain, $ssl, $port ) = split( /\|/, Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} ) );
$ssl  = int($ssl);
$port = $port ? $port : $ssl ? '2078' : '2077';

my $url       = ( $ssl ? 'https://' : 'http://' ) . $domain . ':' . $port . '/';
my $secure    = $ssl ? 'Secure ' : '';
my $txtsecure = $ssl ? 'Secure ' : '';
my $usecure   = $ssl ? 'Secure_' : '';

print <<EOM;
Content-Type: application/download; name="${domain} ${secure}WebDisk.vbs";
Content-Disposition: attachment; filename="${domain} ${secure}WebDisk.vbs";

EOM

open( my $wdisk_fh, '<', '/usr/local/cpanel/base/backend/webdisk.vbs' );
while ( readline($wdisk_fh) ) {
    s/\%domain\%/$domain/g;
    s/\%url\%/$url/g;
    s/\%txtsecure\%/$txtsecure/g;
    s/\%secure\%/$secure/g;
    s/\%usecure\%/$usecure/g;
    print;
}
close($wdisk_fh);
