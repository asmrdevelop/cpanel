package Cpanel::SpriteGen_ExtPerlMod;

# cpanel - Cpanel/SpriteGen_ExtPerlMod.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use GD           ();
use Carp         ();
use Cpanel::Carp ();
Cpanel::Carp::enable();
use Cpanel::Logger           ();
use Cpanel::FileUtils::Write ();

our $VERSION = '1.2';

my $logger      = Cpanel::Logger->new();
my $SNAP_OFFSET = 300;

my $MAX_GIF_PIXELS = 8192;

sub generate {    ## no critic qw(Subroutines::ProhibitExcessComplexity)
    my ($rargs) = @_;
    alarm(300);

    my %SPRITEBANK;
    my $compression = $rargs->{'spritecompression'} ? $rargs->{'spritecompression'} : 100;
    my $outfile     = $rargs->{'spritefile'};
    my $type        = $rargs->{'spritetype'};
    my $method      = $rargs->{'spritemethod'};
    my $format      = $rargs->{'spriteformat'} || 'jpg';
    my $direction   = 'vertical';

    #my $direction   = 'horizontal';
    my $masterw = 0;
    my $masterh = 0;
    my $allsize = 0;

    my $jpegbleedw  = $format eq 'jpg'                    ? 2            : 0;
    my $jpegbleedh  = $format eq 'jpg'                    ? 2            : 0;
    my $snap_offset = $method eq 'snap_to_smallest_width' ? $SNAP_OFFSET : 0;

    if ( $method eq 'snap_to_smallest_width' || exists $rargs->{'filelist'}->{'bg'} ) {
        $direction = 'vertical';
    }
    my $file_count = scalar keys %{ $rargs->{'fileslist'} };
    if ( $file_count == 0 ) {
        print STDERR "No files in the file list.  Skipping this sprite.\n";
        return;
    }

    # This is actually ok for some branding packages
    #elsif ( $file_count == 1 ) {
    #    print STDERR "Only one file specified for sprite. This cannot be correct.\n";
    #    return;
    #}

    foreach my $sprite ( sort bglast keys %{ $rargs->{fileslist} } ) {
        my $file  = $rargs->{fileslist}->{$sprite};
        my $size  = ( stat($file) )[7];
        my $isgif = 0;

        my $spriteimg;
        if ( $method =~ /skip_filetype_(\w+)/ ) {
            next if $file =~ /\.$1$/;
        }
        if ( $method =~ /only_filetype_(\w+)/ ) {
            next if $file !~ /\.$1$/;
        }
        if ( $file =~ /\.jpe?g$/ ) {
            $spriteimg = GD::Image->newFromJpeg( $file, 1 );
        }
        elsif ( $file =~ /\.gif$/ ) {
            $isgif     = 1;
            $spriteimg = GD::Image->newFromGif($file);
        }
        elsif ( $file =~ /\.png$/ ) {
            $spriteimg = GD::Image->newFromPng( $file, 1 );
        }

        if ($spriteimg) {
            my ( $width, $height ) = $spriteimg->getBounds();
            my $image_size = int( $width * $height );

            #gif has a limited color range; no large images
            if ( $isgif && $image_size > $MAX_GIF_PIXELS ) {
                $logger->info("File \"$file\" has $width x $height dimensions with $image_size pixels.\nThis is exceeding $MAX_GIF_PIXELS pixels and color palette issue may be expected when its associated sprite file is used:\n\t \"$outfile\".\n");
            }

            if ( $method =~ /scale_(\d+)percent/ ) {
                my $percent   = ( int($1) / 100 );
                my $newwidth  = int( $width * $percent );
                my $newheight = int( $height * $percent );
                my $scaleimg  = GD::Image->newTrueColor( $newwidth, $newheight );

                if ( $format eq 'png' ) {
                    $scaleimg->saveAlpha(1);
                    $scaleimg->alphaBlending(0);
                }

                $scaleimg->copyResampled( $spriteimg, 0, 0, 0, 0, $newwidth, $newheight, $width, $height );

                $spriteimg = $scaleimg;

                ( $width, $height ) = $spriteimg->getBounds();
            }
            if ( $format eq 'jpg' ) {
                my $antibleedimg = GD::Image->newTrueColor( $width + $jpegbleedw, $height + $jpegbleedh );
                $antibleedimg->copy( $spriteimg, 0, 1, 0, 0, $width, $height );

                #add a line above and below to prevent bleed
                $antibleedimg->copy( $spriteimg, 0, 0,           0, 0,           $width, 1 );
                $antibleedimg->copy( $spriteimg, 0, $height + 1, 0, $height - 1, $width, 1 );

                #add a line to the right to prevent bleed
                $antibleedimg->copy( $spriteimg, $width,     1, $width - 1, 0, 1, $height );
                $antibleedimg->copy( $spriteimg, $width + 1, 1, $width - 1, 0, 1, $height );
                $spriteimg = $antibleedimg;
                ( $width, $height ) = $spriteimg->getBounds();
            }
            elsif ( $format eq 'png' ) {
                $spriteimg->saveAlpha(1);
                $spriteimg->alphaBlending(0);
            }
            if ( $width > 0 && $height > 0 ) {
                $SPRITEBANK{$sprite} = { gdimg => $spriteimg, height => $height, width => $width, size => $size };

                $allsize += $size + $snap_offset;

                if ( $direction eq 'horizontal' ) {
                    $masterw += $width;
                    if ( $height > $masterh ) { $masterh = $height; }
                }
                else {
                    $masterh += $height + $snap_offset;
                    if ( $method eq 'snap_to_smallest_width' ) {
                        if ( $width < $masterw || $masterw == 0 ) {
                            $masterw = $width;
                        }
                    }
                    elsif ( $width > $masterw ) {
                        $masterw = $width;
                    }
                }
            }
        }
    }

    # no need to make the image any bigger since the last part will never overlap
    $masterh -= $snap_offset;
    $allsize -= $snap_offset;

    if ( $masterw == 0 || $masterh == 0 ) {
        $logger->info("Generating Sprite would generate an invalid image [$masterw x $masterh].  Skipping this sprite.");
        return;
    }

    my $curheight = 0;
    my $curwidth  = 0;
    my $masterimg;
    if ( $format eq 'gif' ) {
        $masterimg = GD::Image->newPalette( $masterw, $masterh );
    }
    else {
        $masterimg = GD::Image->newTrueColor( $masterw, $masterh );
    }
    my $bgcolor;
    if ( $format eq 'gif' ) {
        $bgcolor = $masterimg->colorAllocate( 255, 94, 245 );
        $masterimg->transparent($bgcolor);
    }
    elsif ( $format eq 'png' ) {
        $masterimg->saveAlpha(1);
        $masterimg->alphaBlending(0);
    }
    else {
        $bgcolor = $masterimg->colorAllocate( 255, 255, 255 );
    }
    $masterimg->filledRectangle( 0, 0, $masterw, $masterh, $bgcolor );
    $masterimg->interlaced('true');

    my @map_data;

    foreach my $sprite ( sort bglast keys %SPRITEBANK ) {
        $masterimg->copy(
            $SPRITEBANK{$sprite}->{gdimg},
            ( $direction eq 'horizontal' ) ? ( $curwidth, 0 ) : ( 0, $curheight ),
            0, 0,
            @{ $SPRITEBANK{$sprite} }{ 'width', 'height' }
        );

        my $map_hr = {
            img    => $sprite,
            width  => $SPRITEBANK{$sprite}->{width} - $jpegbleedw,
            height => $SPRITEBANK{$sprite}->{height} - $jpegbleedh,
        };

        if ( $direction eq 'horizontal' ) {
            $map_hr->{'position'} = $curwidth + int( $jpegbleedw / 2 );
            $curwidth += $SPRITEBANK{$sprite}->{width};

        }
        else {
            $map_hr->{'position'} = $curheight + int( $jpegbleedh / 2 ), $curheight += $SPRITEBANK{$sprite}->{height} + $snap_offset;
        }

        push @map_data, $map_hr;
    }

    #This custom format is actually faster than using JSON::Syck/Cpanel::JSON.
    #If JSON::XS gets used, then it will make sense to switch.
    my $mapcontents = ( $direction eq 'horizontal' ? '2' : '1' ) . "\n";    #version 1
    $mapcontents .= rand(99999999999) . "\n";
    $mapcontents .= join( q{}, map { "$_->{'img'}:$_->{'position'}:$_->{'width'}x$_->{'height'}\n" } @map_data );
    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( "$outfile.map", $mapcontents, 0644 ) ) {
        $logger->warn("Cannot rebuild sprite map file $outfile.map: $!");
        alarm(0);
        return;                                                             # don't try to rebuild other files if this one fails; they'll be out of sync.
    }

    $logger->debug("Sprite Image ($masterw,$masterh) file = $outfile");
    my $contents;
    if ( $format eq 'png' ) {
        $contents = $masterimg->png(9);
    }
    elsif ( $format eq 'gif' ) {
        $contents = $masterimg->gif();
    }
    else {
        $contents = $masterimg->jpeg($compression);
    }
    if ( !Cpanel::FileUtils::Write::overwrite_no_exceptions( $outfile, $contents, 0644 ) ) {
        $logger->warn("Can't rebuild sprite file $outfile: $!");
        alarm(0);
        return;
    }
    my $outsize    = ( stat($outfile) )[7];
    my $numsprites = scalar keys %SPRITEBANK;
    alarm(0);
    print $numsprites;

    return;
}

sub bglast {
    if ( $a eq 'bg' ) { return 1000; }
    if ( $b eq 'bg' ) { return -1000; }
    return $a cmp $b;
}

1;
