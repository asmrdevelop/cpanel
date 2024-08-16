package Cpanel::Template::Plugin::SVGGradient;

# cpanel - Cpanel/Template/Plugin/SVGGradient.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base 'Template::Plugin';
use MIME::Base64 ();

my $_DEFAULT_WIDTH  = 1;
my $_DEFAULT_HEIGHT = 100;

my $gradient_index = 0;

#based on http://dev.w3.org/csswg/css3-images/#linear-gradients
#returns the data URI string corresponding to the specified gradient
sub linear {
    shift();    #$this
    my $args = shift();

    my $start = $args->{'start'};

    my %coordinates = ( x2 => '0%', y2 => '100%' );
    if ($start) {
        if ( $start =~ m{right} ) {
            $coordinates{'x1'} = '100%';
            $coordinates{'x2'} = '0%';
        }
        elsif ( $start =~ m{left} ) {
            $coordinates{'x2'} = '100%';
        }

        if ( $start =~ m{bottom} ) {
            $coordinates{'y1'} = '100%';
            $coordinates{'y2'} = '0%';
        }
        elsif ( $start =~ m{top} ) {
            $coordinates{'y2'} = '100%';
        }
    }

    my $width  = $args->{'width'}  || $_DEFAULT_WIDTH;
    my $height = $args->{'height'} || $_DEFAULT_HEIGHT;

    my $coordinates_string = join( ' ', map { "$_=\"$coordinates{$_}\"" } keys %coordinates );

    my $id = '__generated_svg_gradient' . $gradient_index++;

    my $svg = qq{
<svg width="$width" height="$height" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="$id" $coordinates_string>};
    my ( $stop, $color, $offset );
    for my $i ( 0 .. $#{ $args->{'stops'} } ) {
        $stop = $args->{'stops'}[$i];
        ( $color, $offset ) = ref($stop) ? @$stop : ( $stop, undef );
        $offset ||= $i / $#{ $args->{'stops'} };

        $svg .= qq{<stop offset="$offset"};
        if ( $color =~ s{rgba}{rgb}i ) {
            $color =~ s{(\(\s*[^,\s]+\s*,\s*[^,\s]+\s*,\s*[^,\s])\s*,\s*([^,\s\)]+)}{$1};
            my $opacity = $2;
            $svg .= qq{ stop-opacity="$opacity"};
        }
        $svg .= qq{ stop-color="$color"/>};
    }

    $svg .= qq{</linearGradient></defs><rect width="$width" height="$height" fill="url(#$id)"/></svg>};

    my $base64;
    if ( $args->{'gzip'} ) {
        require IO::Compress::Gzip;
        my $gzipped;
        IO::Compress::Gzip::gzip( \$svg, \$gzipped );
        $base64 = MIME::Base64::encode_base64( $gzipped, q{} );
    }
    else {
        $base64 = MIME::Base64::encode_base64( $svg, q{} );
    }

    return "data:image/svg+xml;base64,$base64";
}

1;

__END__

Some CSS that would use this:

<style type="text/css">
.yui-dialog .ft span.button-group button {
    background-image: url([% SVGGradient.linear( { start=>'top', stops => [
        [ 'rgba(0,0,0,0.07)', '0%' ],
        [ 'rgba(0,0,0,0.0)', '30%' ],
        [ 'rgba(0,0,0,0.0)', '60%' ],
        [ 'rgba(0,0,0,0.09)', '100%' ],
    ] } ) %]);
}
.yui-dialog .ft span.button-group button:hover {
    background-image: url([% SVGGradient.linear( { start=>'top', stops => [
        [ 'rgba(0,0,0,0.06)', '0%' ],
        [ 'rgba(0,0,0,0.03', '30%' ],
        [ 'rgba(0,0,0,0.01)', '100%' ],
    ] } ) %]);
}

.cjt-notice-success .bd {
    background-image: url([% SVGGradient.linear( { start=>'top', stops => [ '#eaffe0', '#c0d1b6' ] } ) %]);
}
.cjt-notice-success.cjt-notice-closable:hover .bd {
    background-image: url([% SVGGradient.linear( { start=>'top', stops => [ '#c0d1b6', '#daefd0' ] } ) %]);
}

.loader-tool {
    background-image: url([% SVGGradient.linear( { start=>'top', stops => [ '#fdfdfd', '#d1d1d1' ] } ) %]);
}

input[type=submit],
input[type=button] {
    background-image: url([% SVGGradient.linear({ stops => [ '#fbfbfb', '#d9d9d9' ] }) %]);
}
input[type=submit]:hover,
input[type=button]:hover {
    background-image: url([% SVGGradient.linear({ stops => [ '#ebebeb', '#c9c9c9' ] }) %]);
}
input[type=submit]:active,
input[type=button]:active {
    background-image: url([% SVGGradient.linear({ stops => [ '#b9b9b9', '#fbfbfb' ] }) %]);
}
</style>
