#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/traceaddy.cgi              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Cpanel::AdminBin     ();
use Cpanel::Encoder::URI ();

print "Content-type: image/png\r\n\r\n";

eval "use GD;";
my $has_gd = $@ ? 0 : 1;

if ( !$has_gd ) {
    its_broken();
}

my %ROUTE;
my $startaddress;
my $addy = Cpanel::Encoder::URI::uri_decode_str( $ENV{'QUERY_STRING'} );
my $result;

if ( $> != 0 ) {
    $result = Cpanel::AdminBin::adminfetchnocache( 'mailroute', '', 'TRACE', 'storable', $addy, $ENV{REMOTE_USER} );
}
else {
    require Cpanel::EximTrace;
    require Cpanel::Validate::EmailRFC;
    $addy =~ s/%([0-9A-Fa-f]{2})/chr hex $1/eg;
    $addy   = Cpanel::Validate::EmailRFC::scrub($addy);
    $result = Cpanel::EximTrace::generate_trace_table($addy);
}

if ( ref $result eq 'HASH' ) {
    %ROUTE        = %{ $result->{'route'} };
    $startaddress = $result->{'startaddress'};
}
else {
    its_broken();
}
my $maxheight = 1;
my $maxwidth;
my %BOTTOM;
my %SEENLIST;
my $height = 0;
_processnodes($startaddress);

my $image = new GD::Image( ( ( $maxwidth * 150 ) + 600 ), ( $maxheight * 100 ) );
my $font  = '/usr/local/cpanel/share/ttf/Generic.ttf';
my $white = $image->colorAllocate( 255, 255, 255 );
my $black = $image->colorAllocate( 0,   0,   0 );
my $red   = $image->colorAllocate( 255, 0,   0 );
my $green = $image->colorAllocate( 0,   220, 0 );
my $blue  = $image->colorAllocate( 0,   0,   230 );
$image->transparent($white);
$image->interlaced('false');

delete @SEENLIST{ keys %SEENLIST };
$height = 0;
_processnodes( $startaddress, 0, 1 );

binmode(STDOUT);
print STDOUT $image->png;

sub _processnodes {
    my $node  = shift;
    my $width = shift;
    my $img   = shift;

    $SEENLIST{$node} = 1;

    $width++;
    if ( $width > $maxwidth ) { $maxwidth = $width; }

    foreach my $rr ( @{ $ROUTE{$node} } ) {
        my $value = join( ',', %{$rr} );

        if ($img) {
            drawBox( $node, $rr, $width, $height );
        }
        $height++;
        if ( $height > $maxheight ) { $maxheight = $height; }

        if ( ( $$rr{'result'} =~ /\@/ || $$rr{'result'} =~ /^\S+$/ )
            && !$SEENLIST{ $$rr{'result'} } ) {
            _processnodes( $$rr{'result'}, $width, $img );
        }
    }
}

sub drawBox {
    my ( $key, $rr, $depth, $curheight ) = @_;
    my $val = $$rr{'router'};
    if ( $$rr{'aliasfile'} ne '' ) {
        $val .= " via " . $$rr{'aliasfile'};
    }
    elsif ( $$rr{'result'} eq 'local delivery' ) {
        $val .= " to " . $$rr{'result'};
    }
    else {
        $val .= " via " . $$rr{'result'};
    }

    my $x = ( ( $depth - 1 ) * 150 ) + 7;
    my $y = ( $curheight * 100 ) + 4;

    my $bx = ( $depth - 1 );
    my $by = ($curheight);

    #          @bounds[0,1]  Lower left corner (x,y)
    #          @bounds[2,3]  Lower right corner (x,y)
    #          @bounds[4,5]  Upper right corner (x,y)
    #          @bounds[6,7]  Upper left corner (x,y)
    my @boundsa = $image->stringFT( $black, $font, 12.0, 0.0, $x, $y + 15, $key );
    if ($@) {
        my $px = $x;
        my $py = $y + 15;
        $image->string( GD::Font->MediumBold, $x, $y + 15, $key, $black );
        @boundsa = ( $px, $py - 8, $px + ( length($key) * 7 ), $py, $px, $py + ( length($key) + 5 ), $px, $py );
    }
    my @boundsb = $image->stringFT( $black, $font, 12.0, 0.0, $boundsa[0], $boundsa[1] + 20, $val );
    if ($@) {
        my $px = $boundsa[0];
        my $py = $boundsa[1] + 10;
        $image->string( GD::Font->MediumBold, $boundsa[0], $boundsa[1] + 20, $val, $black );
        @boundsb = ( $px, $py, $px + ( length($val) * 7 ), $py + 20, $px, $px + ( length($val) + 5 ), $px, $py );
    }

    my $pngfile     = '';
    my $branchcolor = $black;
    if ( $$rr{'error'} ) {
        $branchcolor = $red;
        $pngfile     = '/usr/local/cpanel/share/icons/alert.red.png';
    }
    elsif ( $$rr{'result'} eq 'local delivery' ) {
        $branchcolor = $blue;
        $pngfile     = '/usr/local/cpanel/share/icons/mbox.png';
    }
    elsif ( $$rr{'aliasfile'} ne '' ) {
        $pngfile = '/usr/local/cpanel/share/icons/f.png';
    }
    else {
        $branchcolor = $green;
        $pngfile     = '/usr/local/cpanel/share/icons/world2.png';
    }

    if ( $boundsb[2] != $boundsa[6] ) {
        if ( $boundsa[2] > $boundsb[2] ) {    #if the first text is longer then the second use it as the rectangle size
            $image->rectangle( $boundsa[6] - 5, $boundsa[7] - 5, $boundsa[2] + 5, $boundsb[3] + 5, $branchcolor );
        }
        else {
            $image->rectangle( $boundsa[6] - 5, $boundsa[7] - 5, $boundsb[2] + 5, $boundsb[3] + 5, $branchcolor );
        }

        #$mbx = ( $bx - 1 );
        for ( my $i = ( $by - 1 ); $i >= 0; $i-- ) {
            if ( $BOTTOM{ $bx - 1 }{$i} ne '' ) {
                $image->line( ( $x - 100 ), $BOTTOM{ $bx - 1 }{$i} + 5, ( $x - 100 ), ( $y + 20 ), $black );
                last;
            }
        }

        $image->line( ( $x - 100 ), ( $y + 20 ), $x - 7, ( $y + 20 ), $branchcolor );

        open( PNG, '<', $pngfile );
        my $myImage = newFromPng GD::Image( \*PNG ) || die;
        close PNG;
        $myImage->transparent($white);
        my ( $imgwidth, $imgheight ) = $myImage->getBounds();

        $image->copy( $myImage, ( $x - 100 ) - ( $imgwidth / 2 ), ( $y + 20 ) - ( $imgheight / 2 ), 0, 0, $imgwidth, $imgheight );

        $BOTTOM{ $bx - 1 }{$by} = ( ( ( $y + 14 ) + ($imgheight) ) - ( $imgheight / 2 ) );
        $BOTTOM{$bx}{$by} = ( $boundsb[3] );
    }
    else {
        if ( $boundsa[2] > $boundsb[2] ) {    #if the first text is longer then the second use it as the rectangle size
            $image->rectangle( $boundsa[6] - 2, $boundsa[7] - 2, $boundsa[2] + 5, $boundsb[3] + 5, $branchcolor );
        }
        else {
            $image->rectangle( $boundsa[6] - 2, $boundsa[7] - 2, $boundsb[2] + 5, $boundsb[3] + 5, $branchcolor );
        }
        $BOTTOM{$bx}{$by} = ( $boundsb[3] - 20 );
    }

}

sub its_broken {
    if ( open my $image_fh, '<', '/usr/local/cpanel/whostmgr/docroot/images/broken.gif' ) {
        binmode $image_fh;
        while ( readline $image_fh ) {
            print;
        }
        close $image_fh;
    }
    exit;
}
