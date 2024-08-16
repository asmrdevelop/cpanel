package Cpanel::SVG::SpriteGenerator;

# cpanel - Cpanel/SVG/SpriteGenerator.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use CSS                      ();
use Cpanel::Exception        ();
use Cpanel::FileUtils::Write ();
use Cpanel::Math             ();
use Cpanel::StringFunc::Case ();
use Cpanel::StringFunc::Trim ();
use SVG                      ();
use SVG::Parser;    # import needed
use XML::LibXML ();

our $FIXED_CSS_NAME      = 'CSSG';
our $XML_NODES_TO_REMOVE = 'sodipodi|metadata';    # Known to break import of Inkscape-created SVG's

my $parser;

=pod

=encoding utf-8

=head1 NAME

Cpanel::SVG::SpriteGenerator - Generate a sprite from SVG files

=head1 SYNOPSIS

  my $svg_props = Cpanel::SVG::SpriteGenerator::make_svg_sprite(
    'prefix'            => 'izzy',
    'source_images'     => [ 'icon.svg', 'icon2.svg', ... ],
    'target_file'       => 'sprite.svg',
    'add_extra_padding' => 5,
    'theme'             => 'jupiter',
    'json_config'       => Cpanel::Branding::Lite::Config::load_theme_config_from_file($theme_config_file),
  );

=head1 DESCRIPTION

This module provides functionality to generate a svg sprite.

=head1 METHODS

=head2 make_svg_sprite

Generate an SVG sprite

=head3 Arguments

A hash with the following keys:

Required:

  prefix            - scalar:   A unique CSS prefix for the sprite (allows multiple sprites on the same page)
  source_images     - arrayref: paths to SVG images
  target_file       - scalar:   path to save the new SVG sprite
  theme             - scalar:   Theme (ex: jupiter) has to be provided
  json_config       - hashref:  Contains Config.json data

Optional:

  add_extra_padding - number:   Pixels to pad each image in the sprite (5 is recommend to work around Safari bugs)

=head3 Return Value

A hashref of the sprite properties

Example:

    {
        'w'      => 101,
        'images' => {
            'addon_domains' => {
                'w' => '48',
                'x' => 0,
                'y' => 0,
                'h' => '48'
            },
            'tls_wizard' => {
                'w' => '48',
                'x' => 53,
                'y' => 0,
                'h' => '48'
            }
        },
        'h' => 48
    }

=cut

my %remove_elements = ( 'svg' => 1, 'g' => 1, 'style' => 1, 'title' => 1, 'defs' => 1 );

sub make_svg_sprite {
    my (%opts) = @_;

    foreach my $required (qw(prefix source_images target_file prefix theme json_config)) {
        die Cpanel::Exception::create( 'MissingParameter', [ 'name' => $required ] ) if !$opts{$required};
    }

    my $extra_padding = $opts{'add_extra_padding'} || 0;
    my $prefix        = $opts{'prefix'};
    my $theme         = $opts{'theme'};
    my $json_config   = $opts{'json_config'};

    my $sprite = SVG->new(
        -inline    => 1,
        -indent    => '',
        -elsep     => '',
        -nocredits => 1,

    );

    my ( $sprite_height, $x ) = ( 0, 0 );
    my %svg_images;
    my $css = '';
    my %class_map;
    my %known_selectors;
    my @groups;
    my $css_selector_counter = 0;

    foreach my $image_path ( @{ $opts{'source_images'} } ) {

        if ( -z $image_path ) {
            warn("WARNING : Unable to load an empty image (please verify the SVG/XML and retry): $image_path\n");
            next;
        }
        my $image_name = _path_to_image_name($image_path);

        if ( $theme =~ /jupiter/i && $json_config->{'icon'}->{'format'} eq 'svg' ) {

            if ( $image_name =~ /^group/i ) {
                _normalize_size(
                    image_path   => $image_path,
                    group_height => $json_config->{'icon'}->{'group'}->{'height'},
                    group_width  => $json_config->{'icon'}->{'group'}->{'width'}
                ) || next;
            }
            else {
                _normalize_size(
                    image_path   => $image_path,
                    group_height => $json_config->{'icon'}->{'feature'}->{'height'},
                    group_width  => $json_config->{'icon'}->{'feature'}->{'width'}
                ) || next;
            }
        }
        my $svg = _parse_svg_from_file($image_path) || return;
        my ( $w, $h ) = _get_width_and_height_from_svg( $svg, $image_name );

        $css .= _make_css_unique_and_dedupe( _get_css_text_from_parsed_svg($svg), $prefix, \$css_selector_counter, \%known_selectors, \%class_map );

        my $svg_nodes_ref = [];
        _load_svg_nodes_to_arrayref( $svg, $svg_nodes_ref );

        _replace_classes_with_unique_class_map( $svg_nodes_ref, \%class_map );

        push @groups, [ $x, $svg_nodes_ref ];
        $svg_images{$image_name} = { 'w' => $w, 'h' => $h, 'x' => $x, 'y' => 0 };
        $sprite_height = $h if $h > $sprite_height;
        $x += $w + $extra_padding;
    }
    $x -= $extra_padding;    # Chomp the last padding add since there is no image after this one

    my $style = $sprite->style( 'type' => 'text/css' );
    $css =~ tr{\n}{}s;
    $style->CDATA($css);

    foreach my $x_group (@groups) {
        my ( $x, $svg_nodes_ref ) = @{$x_group};
        my $group = $sprite->group( 'transform' => "translate($x)" );
        foreach my $element (@$svg_nodes_ref) {
            $group->appendNode($element);
        }
    }
    foreach my $image_name ( sort keys %svg_images ) {
        my ( $x, $y, $h, $w ) = @{ $svg_images{$image_name} }{qw(x y h w)};
        $sprite->view( id => "$prefix-$image_name", viewBox => "$x 0 $w $h" );
    }

    # Width and Height are necessary for Internet Explorer 9 and 10
    # They also can not function as a percentage and must be in pixels
    # Additionally, we need to round up the width (no decimal) so we
    # because some browsers round that size anyways.
    my $sprite_width = Cpanel::Math::ceil($x);

    $sprite->getFirstChild->attr( 'width',  $sprite_width );
    $sprite->getFirstChild->attr( 'height', $sprite_height );

    Cpanel::FileUtils::Write::overwrite(
        $opts{'target_file'},
        $sprite->xmlify(),
        0644
    );

    return { 'w' => $sprite_width, 'h' => $sprite_height, 'images' => \%svg_images };
}

# This function will assign a unique name to each
# css class in order to ensure they do not conflict
# with each other and cause "contamination" of other
# sprites in the document.
my %_parse_cache;

sub _make_css_unique_and_dedupe {
    my ( $css_text, $prefix, $css_selector_counter_ref, $known_selectors_ref, $class_map_ref ) = @_;
    Cpanel::StringFunc::Trim::ws_trim( \$css_text );
    my $css;
    if ( $_parse_cache{$css_text} ) {
        $css = $_parse_cache{$css_text};
    }
    else {
        $css = CSS->new( { 'parser' => 'CSS::Parse::Lite' } );
        $css->read_string($css_text);
        $_parse_cache{$css_text} = $css;
    }
    my $newcss = '';
    for my $style ( @{ $css->{styles} } ) {
        for my $selector_obj ( @{ $style->{selectors} } ) {
            my $selector       = $selector_obj->{'name'};
            my %props          = map { $_->{'property'} => $_->{'simple_value'} } @{ $style->{'properties'} };
            my $selector_token = join( '_', map { tr[a-z][A-Z]r } sort %props );
            my $new_name;
            my $save = 0;
            if ( $known_selectors_ref->{$selector_token} ) {
                $new_name = $known_selectors_ref->{$selector_token};
            }
            else {
                $new_name = $selector;
                $new_name =~ s/\.[_a-zA-Z]+[_a-zA-Z0-9-]*/'.' . $FIXED_CSS_NAME . $prefix .  ++$$css_selector_counter_ref/ge;
                $known_selectors_ref->{$selector_token} = $new_name;
                $save = 1;
            }
            substr( $selector, 0, 1, '' ) if index( $selector, '.' ) == 0;
            substr( $new_name, 0, 1, '' ) if index( $new_name, '.' ) == 0;
            $class_map_ref->{$selector} = $new_name;
            if ($save) {
                $newcss .= ".$new_name\{" . $style->properties() . "\}\n";
            }
        }
    }
    return $newcss;
}

sub _get_width_and_height_from_svg {
    my ( $svg, $image_name ) = @_;

    my ( $w, $h );
    if ( my $viewBox = $svg->attr('viewBox') ) {
        ( $w, $h ) = $viewBox =~ m{[0-9.]+ [0-9.]+ ([0-9.]+) ([0-9.]+)};
    }
    if ( my $width = $svg->attr('width') ) {
        ($w) = $width =~ m{([0-9.]+)};
    }
    if ( my $height = $svg->attr('height') ) {
        ($h) = $height =~ m{([0-9.]+)};
    }

    if ( !$w || !$h ) {
        die "The image “$image_name” is missing the width or height";
    }

    return ( $w, $h );
}

sub _replace_classes_with_unique_class_map {
    my ( $svg_nodes_ref, $class_map_ref ) = @_;
    foreach my $element ( @{$svg_nodes_ref} ) {
        if ( my $classes = $element->getAttribute('class') ) {
            $element->setAttribute( 'class', map { $class_map_ref->{$_} } split( ' ', $classes ) );
        }
    }
    return 1;
}

sub _path_to_image_name {
    my ($image_path) = @_;
    my $image_name = File::Basename::basename($image_path);
    $image_name =~ s/\.svg$//;
    return $image_name;
}

sub _get_css_text_from_parsed_svg {
    my ($svg) = @_;

    my $style_element = ( $svg->getElements('style') )[0];
    my $csstext       = defined $style_element ? $style_element->getCDATA() : '';

    return $csstext;
}

sub _load_svg_nodes_to_arrayref {
    my ( $svg, $svg_nodes_ref ) = @_;

    foreach my $element ( $svg->getChildren() ) {
        my $element_name = Cpanel::StringFunc::Case::ToLower( $element->getElementName() );
        if ( $element->hasChildren() ) {
            _load_svg_nodes_to_arrayref( $element, $svg_nodes_ref );
        }
        elsif ( $remove_elements{$element_name} ) {
            next;
        }
        else {
            push @$svg_nodes_ref, $element;
        }
    }

    return 1;
}

sub _parse_svg_from_file {
    my ($image_path) = @_;

    $parser ||= SVG::Parser->new( '--indent' => '', '--elsep' => '' );
    my $svg = eval { $parser->parse_file($image_path)->getFirstChild() };
    if ( $@ || !$svg ) {
        warn("WARNING : Unable to get child node (please verify the SVG/XML and retry): $image_path \nSVG Exception : $@");
        return 0;
    }

    return $svg;
}

# If SVG image size properties are set in sub-nodes under
# the top-level root node, then perl's SVG module isn't
# able to edit or override them.  _normalize_size identifies
# this case, and scales them down if they're over the limit.
sub _normalize_size {
    my %args = @_;

    $args{'update_flag'} = 0;
    my $xml = eval { 'XML::LibXML'->load_xml( location => $args{'image_path'}, no_blanks => 1 ) };
    if ( $@ || !$xml ) {
        warn("WARNING : Unable to load image (please verify the SVG/XML and retry $args{'image_path'} \nSVG Exception : $@");
        return 0;
    }
    my $root = $xml->documentElement();
    _recurs_search( $root, \%args );
    _write_to_SVG( $root, $args{'image_path'} ) if ( $args{'update_flag'} );

    return 1;
}

sub _validate_image_size {
    my ( $child, $args ) = @_;

    return if !$child->can('hasAttribute');

    if ( $child->nodeName =~ /^($XML_NODES_TO_REMOVE)/i ) {
        $child->unbindNode;
        $args->{'update_flag'}++;
    }

    if ( $child->hasAttribute('height') || $child->hasAttribute('width') ) {
        my $height = $child->getAttribute('height');
        if ( length $height > 0 ) {
            if ( _prune_unit_id($height) > $args->{'group_height'} ) {
                $args->{'update_flag'}++;
                $child->setAttribute( 'height' => $args->{'group_height'} );
                warn("WARNING : ICON height is over maximum. Setting to $args->{'group_height'}.\n");
            }
        }

        my $width = $child->getAttribute('width');
        if ( length $width > 0 ) {
            if ( _prune_unit_id($width) > $args->{'group_width'} ) {
                $args->{'update_flag'}++;
                $child->setAttribute( 'width' => $args->{'group_width'} );
                warn("WARNING : ICON width is over maximum. Setting to $args->{'group_width'}.\n");
            }
        }
    }

    return 1;
}

# SVG allows 2-letter unit identifiers, defaults to pixels - px.
# Without finding a module to convert them, we simply drop the identifier,
# and convert to the spec'd number of pixels.
# We only make a change when a number is found over the spec, no matter
# which unit identifier is given.
sub _prune_unit_id {
    my $param = shift;

    my ( $num, $unit_id ) = $param =~ /(^\d+[\d.]*)\s*([a-zA-Z]{2})?/;
    if ( length $unit_id && $unit_id !~ /^px$/i ) {
        warn("WARNING : ICON height or width not in pixels: $param\n");
    }

    return $num;
}

sub _recurs_search {
    my ( $node, $args ) = @_;

    # reached end of recursion
    return if ( !$node );

    _validate_image_size( $node, $args );

    if ( $node->hasChildNodes() ) {
        foreach my $child ( $node->childNodes ) {
            _recurs_search( $child, $args );
        }
    }

    return;
}

sub _write_to_SVG {
    my ( $data, $imagepath ) = @_;

    Cpanel::FileUtils::Write::overwrite(
        $imagepath,
        $data->toString(1)
    );

    return;
}

1;
