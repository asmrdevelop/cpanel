#!/usr/local/cpanel/3rdparty/bin/perl

# cpanel - base/backend/piegraph.cgi               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

my %RGB = (
    white   => [ 0xFF, 0xFF, 0xFF ],
    lgray   => [ 0xBF, 0xBF, 0xBF ],
    gray    => [ 0x7F, 0x7F, 0x7F ],
    dgray   => [ 0x3F, 0x3F, 0x3F ],
    black   => [ 0x00, 0x00, 0x00 ],
    lblue   => [ 0x00, 0x00, 0xFF ],
    blue    => [ 0x00, 0x00, 0xBF ],
    dblue   => [ 0x00, 0x00, 0x7F ],
    gold    => [ 0xFF, 0xD7, 0x00 ],
    lyellow => [ 0xFF, 0xFF, 0x00 ],
    yellow  => [ 0xBF, 0xBF, 0x00 ],
    dyellow => [ 0x7F, 0x7F, 0x00 ],
    lgreen  => [ 0x00, 0xFF, 0x00 ],
    green   => [ 0x00, 0xBF, 0x00 ],
    dgreen  => [ 0x00, 0x7F, 0x00 ],
    lred    => [ 0xFF, 0x00, 0x00 ],
    red     => [ 0xBF, 0x00, 0x00 ],
    dred    => [ 0x7F, 0x00, 0x00 ],
    lpurple => [ 0xFF, 0x00, 0xFF ],
    purple  => [ 0xBF, 0x00, 0xBF ],
    dpurple => [ 0x7F, 0x00, 0x7F ],
    lorange => [ 0xFF, 0xB7, 0x00 ],
    orange  => [ 0xFF, 0x7F, 0x00 ],
    pink    => [ 0xFF, 0xB7, 0xC1 ],
    dpink   => [ 0xFF, 0x69, 0xB4 ],
    marine  => [ 0x7F, 0x7F, 0xFF ],
    cyan    => [ 0x00, 0xFF, 0xFF ],
    lbrown  => [ 0xD2, 0xB4, 0x8C ],
    dbrown  => [ 0xA5, 0x2A, 0x2A ],
);

use strict;
use Cpanel::Form ();
use HTTP::Date   ();
use GD;
use GD::Graph::pie;
use GD::Graph::bars;
use GD::Graph::hbars;
use GD::Graph::Data;

my %FORM    = Cpanel::Form::parseform();
my @PCOLORS = ( 'lred', 'lgreen', 'lblue', 'lyellow', 'lpurple', 'cyan', 'lorange', 'lbrown', 'gold', 'gray', 'red', 'green', 'blue', 'yellow', 'purple', 'pink', 'orange', 'lgray', 'dred', 'dgreen', 'dblue', 'dyellow', 'dpurple', 'dbrown', 'dpink', 'black', 'white', 'dgray' );

my (@COLORS) = (@PCOLORS) x 11;

my $maxage  = 864000;
my $headers = "Cache-Control: max-age=$maxage, public\r\n" .         #
  "Expires: " . HTTP::Date::time2str( time() + $maxage ) . "\r\n"    #
  . "Content-type: image/png\r\n\r\n";

if ( $FORM{'action'} eq "pie" ) {

    my @data     = ( [], [] );
    my $okvalues = 0;
    my $max_value_length;
    foreach my $key ( sort { $a <=> $b } keys %FORM ) {
        next if ( int($key) == 0 );

        my $value = $FORM{$key};
        if ($value) {
            push( @{ $data[0] }, '' );
            push( @{ $data[1] }, int($value) );
            if ( length $value > $max_value_length ) {
                $max_value_length = length $value;
            }
            $okvalues = 1 if $value > 0;
        }
        else {
            splice( @COLORS, scalar( @{ $data[0] } ), 1 );
        }
    }

    #
    # GD::Graph::pie chokes with large values
    # so we need to reduce them before sending
    # in the data.  This is safe to do since
    # we only care that the numbers display as a percentage
    # of each other.
    #
    my $reduction_factor = 10**( $max_value_length - 2 );
    if ( $reduction_factor > 1 ) {
        for my $value ( 0 .. $#{ $data[1] } ) {
            $data[1]->[$value] = int( $data[1]->[$value] / $reduction_factor );
        }
    }

    if ( $okvalues == 0 ) {
        my $im    = new GD::Image( 120, 120 );
        my $white = $im->colorAllocate( 255, 255, 255 );
        my $black = $im->colorAllocate( 0,   0,   0 );
        $im->transparent($white);
        binmode STDOUT;
        print $headers . $im->png;
    }
    else {
        my $my_graph = new GD::Graph::pie( 120, 120 );
        $my_graph->set(
            axislabelclr => 'black',
            '3d'         => 0,
            pie_height   => 16,
            l_margin     => 0,
            r_margin     => 0,
            start_angle  => 235,
            transparent  => 1,
            dclrs        => \@COLORS,
        );

        print $headers . $my_graph->plot( \@data )->png;
    }
}
else {
    my $im = new GD::Image( 18, 18 );
    my @CA = @{ $RGB{ $COLORS[ $FORM{color} ] } };

    my $r     = $CA[0];
    my $g     = $CA[1];
    my $b     = $CA[2];
    my $color = $im->colorAllocate( $r, $g, $b );

    my $black = $im->colorAllocate( 0, 0, 0 );
    $im->filledRectangle( 0, 0, 18, 18, $black );
    $im->filledRectangle( 2, 2, 16, 16, $color );
    binmode STDOUT;
    print $headers . $im->png;
}
