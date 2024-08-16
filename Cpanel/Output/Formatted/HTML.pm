package Cpanel::Output::Formatted::HTML;

# cpanel - Cpanel/Output/Formatted/HTML.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $VERSION = '1.0';

use base 'Cpanel::Output::Formatted';

use Cpanel::Encoder::Tiny ();

our %STYLE_MAP = (
    'on_red'    => 'errormsg',
    'on_yellow' => 'warningmsg',
    'on_green'  => 'okmsg',
    'yellow'    => 'warningmsg',
    'red'       => 'errormsg',
    'green'     => 'okmsg',
);

sub _color_to_class {
    my ( $self, $color ) = @_;

    return join( ' ', map { $STYLE_MAP{$_} ? $STYLE_MAP{$_} : 'cpanel_output_color_' . $_ } split( m{ }, $color ) );
}

sub _new_line {
    my ($self) = @_;
    return "<br />\n";
}

sub _indent {
    my ($self) = @_;

    return '' if !$self->{'_indent_level'};
    return "<span class='cpanel_output_indent'></span>" x $self->{'_indent_level'};
}

sub _format_text {
    my ( $self, $color, $text ) = @_;

    return $color
      ? "<span class='" . $self->_color_to_class($color) . "'>" . Cpanel::Encoder::Tiny::safe_html_encode_str($text) . "</span>"
      : Cpanel::Encoder::Tiny::safe_html_encode_str($text);
}

1;

__END__
