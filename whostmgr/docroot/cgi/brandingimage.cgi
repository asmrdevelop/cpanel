#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - whostmgr/docroot/cgi/brandingimage.cgi  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use Cpanel                     ();
use Cpanel::Form               ();
use Cpanel::AccessIds::SetUids ();

my %EXTLIST = ( 'jpg' => 'image/jpeg', 'gif' => 'image/gif', 'png' => 'image/png' );
my %FORM    = Cpanel::Form::parseform();

my $imagefile = $FORM{'img'};
my $theme     = $FORM{'theme'};
my $homedir   = ( getpwnam( $ENV{'REMOTE_USER'} ) )[7];

$theme     =~ s/\///g;
$theme     =~ s/[^\w\.\-]//g;
$theme     =~ s/\.\.//g;
$imagefile =~ s/\///g;
$imagefile =~ s/[^\w\.\-]//g;
$imagefile =~ s/\.\.//g;

my ( $euser, $owner_homedir ) = _setup_branding_vars();

Cpanel::AccessIds::SetUids::setuids($euser) || do {
    print "Content-type: text/html\r\n\r\nCould not resolve username\n";
    exit;
};

foreach my $ext ( keys %EXTLIST ) {
    serv_image_file( $ext, "$owner_homedir/cpanelbranding/${theme}/${imagefile}.$ext" ) if -e "$owner_homedir/cpanelbranding/${theme}/${imagefile}.$ext";
}
foreach my $ext ( keys %EXTLIST ) {
    serv_image_file( $ext, "/usr/local/cpanel/base/frontend/${theme}/branding/${imagefile}.$ext" ) if -e "/usr/local/cpanel/base/frontend/${theme}/branding/${imagefile}.$ext";
}

sub serv_image_file {
    my ( $ext, $imagefile ) = @_;
    my $mime_type = $EXTLIST{$ext};
    my $size      = ( stat(_) )[7];

    print "Content-Length: $size\r\nContent-type: $mime_type\r\n\r\n";
    if ( open( my $image_fh, '<', $imagefile ) ) {
        binmode $image_fh;
        my $total_bytes_read = 0;
        my $buffer;
        while ( my $bytesread = read( $image_fh, $buffer, 32768 ) ) {
            $total_bytes_read += $bytesread;
            print $buffer;
        }
        close $image_fh;
    }
    exit;
}

sub _setup_branding_vars {
    my $euser         = $Cpanel::user    = $ENV{'REMOTE_USER'} eq 'root' ? 'cpanel'               : $ENV{'REMOTE_USER'};
    my $owner_homedir = $Cpanel::homedir = $ENV{'REMOTE_USER'} eq 'root' ? $Cpanel::cpanelhomedir : $homedir;

    return ( $euser, $owner_homedir );
}
