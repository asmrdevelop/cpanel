package Cpanel::Template::Plugin::HTMLOptions;

# cpanel - Cpanel/Template/Plugin/HTMLOptions.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use base 'Template::Plugin';

use Cpanel::Encoder::Tiny ();

sub load {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'list', 'options_as_html', \&options_as_html );

    return $class;
}

sub options_as_html {
    my $data = shift;
    if ( UNIVERSAL::isa( $data, 'Template::Plugin' ) ) {
        $data = shift;
    }
    my %OPTS = %{ shift() };

    my $value    = $OPTS{'value'};       # This is the value="" field inside a <option> tag
    my $text     = $OPTS{'text'};        # This is the text that is enclosed in the <option>TEXT</option> tags
    my $selected = $OPTS{'selected'};    # This is the element that should be marked as selected
    my $class    = $OPTS{'class'};       # This is the class name to apply to the element

    if ( defined $selected ) {
        return join(
            '',
            map { sprintf( '<option %s%s value="%s">%s</option>', ( $_->{$class} ? "class='$_->{$class}' " : '' ), ( $_->{$value} eq $selected ? 'selected="selected"' : '' ), ( $_->{$value} =~ tr/&<>"'// ? Cpanel::Encoder::Tiny::safe_html_encode_str( $_->{$value} ) : $_->{$value} ), ( $_->{$text} =~ tr/&<>"'// ? Cpanel::Encoder::Tiny::safe_html_encode_str( $_->{$text} ) : $_->{$text} ) ) }
              @{$data}
        ) . "\n";
    }
    else {
        return join( '', map { sprintf( '<option %svalue="%s">%s</option>', ( $_->{$class} ? "class='$_->{$class}' " : '' ), ( $_->{$value} =~ tr/&<>"'// ? Cpanel::Encoder::Tiny::safe_html_encode_str( $_->{$value} ) : $_->{$value} ), ( $_->{$text} =~ tr/&<>"'// ? Cpanel::Encoder::Tiny::safe_html_encode_str( $_->{$text} ) : $_->{$text} ) ) } @{$data} ) . "\n";
    }
}

1;
