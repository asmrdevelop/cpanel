package Cpanel::ImageManager;

# cpanel - Cpanel/ImageManager.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use vars qw(@ISA @EXPORT $VERSION);    ## no critic qw(ProhibitAutomaticExportation) - legacy code

use Cpanel::Binaries                      ();
use Cpanel::Encoder::Tiny                 ();
use Cpanel::SafeDir                       ();
use Cpanel::SafeDir::Fixup                ();
use Cpanel::SafeRun::Simple               ();
use Cpanel::Server::Type::Role::WebServer ();

$VERSION = '1.0';

my $identify_bin = Cpanel::Binaries::path('identify');
my $convert_bin  = Cpanel::Binaries::path('convert');

sub ImageManager_init {
    return (1);
}

sub ImageManager_dimensions {
    my ( $dir, $file, $re ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }
    return if !main::hasfeature("cpanelpro_images");

    $file =~ s/\///g;
    my $image_file = Cpanel::SafeDir::safedir($dir) . '/' . $file;

    my $rout = Cpanel::SafeRun::Simple::saferun( $identify_bin, $image_file );
    if ($re) {
        if ( $rout =~ /(\d+x\d+)/ ) {
            return $1;
        }
        else {
            return;

        }
    }
    else {
        my $safe_rout = Cpanel::Encoder::Tiny::safe_html_encode_str($rout);
        print $safe_rout;
        return;
    }
}

sub ImageManager_scale {    ## no critic qw(Subroutines::ProhibitManyArgs)
    my ( $dir, $file, $oldimage, $width, $height, $keepold ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }
    return if !main::hasfeature("cpanelpro_images");

    $file =~ s/\///g;
    my $image_file      = Cpanel::SafeDir::safedir($dir) . '/' . $file;
    my $safe_image_file = Cpanel::Encoder::Tiny::safe_html_encode_str($image_file);
    my $old_image_file  = Cpanel::SafeDir::Fixup::homedirfixup($oldimage);

    if ( !-f $image_file ) {
        print "The file does not exist $safe_image_file!\n";
        return ();
    }

    system( $convert_bin, "-size", "${width}x${height}", $image_file, "-resize", "${width}x${height}", $image_file . '.cPscale' );
    if ($keepold) {
        system( 'mv', '-f', $image_file, $old_image_file );
    }
    system( 'mv', '-f', $image_file . '.cPscale', $image_file );
    return;
}

sub _convert {
    my ( $oldfile, $newtype ) = @_;

    my $newfile = $oldfile;

    return if ( $newfile =~ /\.${newtype}/ );

    $newfile =~ s/\.?[^\.]+$//g;

    if ( $newfile eq "" ) { $newfile = $oldfile; }

    $newfile .= "\.${newtype}";

    my $safe_new_file      = Cpanel::SafeDir::Fixup::homedirfixup($newfile);
    my $html_safe_new_file = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_new_file);
    my $safe_old_file      = Cpanel::SafeDir::Fixup::homedirfixup($oldfile);
    my $html_safe_old_file = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_old_file);

    print "Converting ${html_safe_old_file} to ${html_safe_new_file}.......";
    system( $convert_bin, "${safe_old_file}", "${safe_new_file}" );
    if ( !-e $safe_new_file ) {
        print "....Failed (not a valid image file)!\n";

    }
    else {
        print "....Done\n";
    }
    return;
}

sub ImageManager_thumbnail {
    my ( $dir, $wperc, $hperc ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    my $thumb_list_ref = _get_thumb_list_ref( $dir, $wperc, $hperc );

    if ( !$thumb_list_ref ) { print "No Images to thumbnail\n"; return; }
    foreach my $image_ref ( @{$thumb_list_ref} ) {
        my $safe_file          = Cpanel::SafeDir::Fixup::homedirfixup( $image_ref->{'file'} );
        my $html_safe_file     = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_file);
        my $safe_new_file      = Cpanel::SafeDir::Fixup::homedirfixup( $image_ref->{'new_file'} );
        my $html_safe_new_file = Cpanel::Encoder::Tiny::safe_html_encode_str($safe_new_file);

        print "Thumbnailing...$html_safe_file ($image_ref->{'old_width'}x$image_ref->{'old_height'})...";
        print Cpanel::SafeRun::Simple::saferun( $convert_bin, '-size', $image_ref->{'new_width'} . 'x' . $image_ref->{'new_height'}, $safe_file, '-resize', $image_ref->{'new_width'} . 'x' . $image_ref->{'new_height'}, $safe_new_file );

        print "wrote...$html_safe_new_file (" . $image_ref->{'new_width'} . 'x' . $image_ref->{'new_height'} . ")...Done\n";
    }
    return;
}

sub _get_thumb_list_ref {
    my ( $dir, $wperc, $hperc ) = @_;
    my $html_safe_dir = Cpanel::Encoder::Tiny::safe_html_encode_str($dir);

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print 'Sorry, this feature is disabled in demo mode.';
        return;
    }
    return if !main::hasfeature('cpanelpro_images');

    $wperc = ( $wperc / 100 );
    $hperc = ( $hperc / 100 );

    if ( !-d "${dir}" ) {
        print "The directory does not exist ${html_safe_dir}!\n";
        return ();
    }
    if ( !-d "${dir}/thumbnails" ) {
        mkdir( "${dir}/thumbnails", 0755 );
    }

    my @OUTLIST;
    opendir( my $dir_fh, $dir );
    while ( my $file = readdir($dir_fh) ) {
        next if ( $file =~ /^\./ || -d $dir . '/' . $file );
        my $dims = ImageManager_dimensions( ${dir}, ${file}, 1 );
        if ($dims) {
            $dims =~ /(\d+)x(\d+)/;
            my $width  = ( $1 * $wperc );
            my $height = ( $2 * $hperc );
            push @OUTLIST, {
                'file'       => $dir . '/' . $file,
                'old_width'  => $1,
                'old_height' => $2,
                'new_width'  => $width,
                'new_height' => $height,
                'new_file'   => "$dir/thumbnails/tn_$file"

            };
        }
    }
    closedir($dir_fh);
    return \@OUTLIST;

}

sub ImageManager_convert {
    my ( $target, $newtype ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    if ( $Cpanel::CPDATA{'DEMO'} eq '1' ) {
        print "Sorry, this feature is disabled in demo mode.";
        return;
    }
    return if !main::hasfeature("cpanelpro_images");

    my $safe_target = Cpanel::SafeDir::Fixup::homedirfixup($target);

    if ( -d "${safe_target}" ) {
        opendir( DIR, $safe_target );
        my @FILES = readdir(DIR);
        closedir(DIR);
        foreach my $file (@FILES) {
            my $prevfile = "${safe_target}/${file}";
            next if ( !-f $prevfile );
            _convert( $prevfile, $newtype );
        }
    }
    else {
        _convert( $safe_target, $newtype );
    }
    return;
}

sub ImageManager_hdimension {
    my ( $dir, $file ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    return if !main::hasfeature("cpanelpro_images");

    my $dims = ImageManager_dimensions( $dir, $file, 1 );
    $dims =~ /^\d+x(\d+)/;
    print $1;
    return;
}

sub ImageManager_wdimension {
    my ( $dir, $file ) = @_;

    return if !Cpanel::Server::Type::Role::WebServer->is_enabled();

    return if !main::hasfeature("cpanelpro_images");

    my $dims = ImageManager_dimensions( $dir, $file, 1 );
    $dims =~ /^(\d+)/;
    print $1;
    return;
}

our %API = ( thumbnail => { allow_demo => 1 } );

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
