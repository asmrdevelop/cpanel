package Cpanel::Template::Plugin::CPGraph;

# cpanel - Cpanel/Template/Plugin/CPGraph.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::Locale ();

my $locale;

sub _locale {
    $locale ||= Cpanel::Locale->get_handle();
    return $locale;
}

our $DEFAULT_SATURATION = 0.7;
our $DEFAULT_BRIGHTNESS = 0.6;

sub new {
    my ($class) = @_;

    return bless {
        'DEFAULT_SATURATION' => $DEFAULT_SATURATION,
        'DEFAULT_BRIGHTNESS' => $DEFAULT_BRIGHTNESS,
    }, $class;
}

sub get_graph_colors_css {
    my ( $plugin, $color_count, $saturation, $brightness ) = @_;

    $saturation ||= $DEFAULT_SATURATION;
    $brightness ||= $DEFAULT_BRIGHTNESS;

    my $hue_interval = 360 / $color_count;

    my @css_colors = map { hsv_to_rgb_css( undef, $_ * $hue_interval, $saturation, $brightness ) } ( 0 .. $color_count - 1 );

    return \@css_colors;
}

#make sure a given value is between 0 and 1; shift as needed
sub _normalize {
    my $value = shift();

    if ( $value < 0 ) {
        $value = 1 + abs( $value - int($value) );
    }
    elsif ( $value > 1 ) {
        $value = abs( $value - int($value) );
    }

    return $value;
}

#----------------------------------------------------------------------
sub hsl_to_rgb_css {
    my $joined = join( ',', map { int } hsl_to_rgb(@_) );
    return "rgb($joined)";
}

#0-360, 0-1, 0-1
#negatives for hue are ok
sub hsl_to_rgb {
    my ( $r, $g, $b );
    my ( undef, $h, $s, $l ) = @_;

    if ( $s == 0 ) {
        $r = $g = $b = 255;
    }
    else {
        my $m2 =
          ( $l <= 0.5 )
          ? $l + ( $l * $s )
          : $l + $s - ( $l * $s );
        my $m1 = $l * 2 - $m2;

        my $h_prime = $h / 360;

        $r = _hue_to_rgb( $m1, $m2, $h_prime + 1 / 3 );
        $g = _hue_to_rgb( $m1, $m2, $h_prime );
        $b = _hue_to_rgb( $m1, $m2, $h_prime - 1 / 3 );
    }

    return ( $r, $g, $b );
}

sub _hue_to_rgb {
    my ( $m1, $m2, $h_prime ) = @_;
    my $v;

    $h_prime = _normalize($h_prime);

    if ( $h_prime < 1 / 6 ) {
        $v = $m1 + ( 6 * ( $m2 - $m1 ) * $h_prime );
    }
    elsif ( $h_prime < 0.5 ) {
        $v = $m2;
    }
    elsif ( $h_prime < 2 / 3 ) {
        $v = $m1 + ( 6 * ( $m2 - $m1 ) * ( 2 / 3 - $h_prime ) );
    }
    else {
        $v = $m1;
    }

    return 255 * $v;
}

#----------------------------------------------------------------------
sub hsv_to_rgb_css {
    my $joined = join( ',', map { sprintf '%.0f', $_ } hsv_to_rgb(@_) );
    return "rgb($joined)";
}

# http://easyrgb.com/index.php?X=MATH&H=21#text21
#0-360, 0-1, 0-1; negatives are ok
sub hsv_to_rgb {
    my ( undef, $h, $s, $v ) = @_;
    my ( $r, $g, $b );

    $h = _normalize( $h / 360 );

    if ( $s == 0 ) {    #HSV from 0 to 1
        $r = $g = $b = $v;
    }
    else {
        my $var_h = $h * 6;
        if ( $var_h == 6 ) {
            $var_h = 0;    #H must be < 1
        }

        my $var_i = int $var_h;
        my $var_1 = $v * ( 1 - $s );
        my $var_2 = $v * ( 1 - $s * ( $var_h - $var_i ) );
        my $var_3 = $v * ( 1 - $s * ( 1 - ( $var_h - $var_i ) ) );

        if ( $var_i == 0 ) {
            $r = $v;
            $g = $var_3;
            $b = $var_1;
        }
        elsif ( $var_i == 1 ) {
            $r = $var_2;
            $g = $v;
            $b = $var_1;
        }
        elsif ( $var_i == 2 ) {
            $r = $var_1;
            $g = $v;
            $b = $var_3;
        }
        elsif ( $var_i == 3 ) {
            $r = $var_1;
            $g = $var_2;
            $b = $v;
        }
        elsif ( $var_i == 4 ) {
            $r = $var_3;
            $g = $var_1;
            $b = $v;
        }
        else {
            $r = $v;
            $g = $var_1;
            $b = $var_2;
        }
    }

    $r *= 255;    #RGB results from 0 to 255
    $g *= 255;
    $b *= 255;

    return ( $r, $g, $b );
}

#----------------------------------------------------------------------

#takes a list and gives back a list of [val,label] tick pairs
#5 ticks, including empty zero
my $_Number_of_Ticks = 5;

sub get_graph_ticks {
    my ( $plugin, $data_ar ) = @_;
    my $tick_count;

    my $tick_divisor = ( $tick_count || $_Number_of_Ticks ) - 1;

    my @ticks = ( [ 0, q{ } ] );

    my $max_val = int( ( sort { $b <=> $a } @$data_ar )[0] );
    return if !$max_val;

    my $digits     = length int $max_val;
    my $left_digit = int( $max_val / ( 10**( $digits - 1 ) ) );

    my $new_left_digit = $left_digit + ( $left_digit % 2 ? 1 : 2 );

    my $max_tick      = $new_left_digit * ( 10**( $digits - 1 ) );
    my $tick_interval = $max_tick / $tick_divisor;

    push @ticks, map {
        my $cur_tick = $_ * $tick_interval;
        [ $cur_tick, _locale()->numf($cur_tick) ]
    } ( 1 .. $tick_divisor );

    return @ticks;
}

1;
