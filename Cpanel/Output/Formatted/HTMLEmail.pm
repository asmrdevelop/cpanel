package Cpanel::Output::Formatted::HTMLEmail;

# cpanel - Cpanel/Output/Formatted/HTMLEmail.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.1';

use base 'Cpanel::Output::Formatted::HTML';

use Cpanel::Encoder::Tiny ();

our %STYLE_MAP = (
    'on_red'    => '#dc322f',
    'on_yellow' => '#b58900',
    'on_green'  => '#859900',
    'yellow'    => '#b58900',
    'red'       => '#dc322f',
    'green'     => '#859900',
);

sub _color_to_class {
    my ( $self, $color ) = @_;

    return join( ' ', map { $STYLE_MAP{$_} ? $STYLE_MAP{$_} : () } split( m{ }, $color ) );
}

sub _indent {
    my ($self) = @_;

    return '' if !$self->{'_indent_level'};
    return "<span style='width: 15px; display:inline-block;'></span>" x $self->{'_indent_level'};
}

sub _format_text {
    my ( $self, $color, $text ) = @_;

    return $color
      ? "<span style='font-weight: bold; color: " . $self->_color_to_class($color) . ";'>" . Cpanel::Encoder::Tiny::safe_html_encode_str($text) . "</span>"
      : Cpanel::Encoder::Tiny::safe_html_encode_str($text);
}

1;

__END__
