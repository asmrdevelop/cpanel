package Cpanel::Template::Plugin::Encoder;

# cpanel - Cpanel/Template/Plugin/Encoder.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use base 'Template::Plugin';
use Cpanel::Encoder::Tiny ();
use Cpanel::Encoder::URI  ();

my ( %URI_CACHE, %HTML_CACHE );

sub new {
    my ( $class, $context ) = @_;

    $context->define_vmethod( 'scalar', 'cpanel_uri_encode_str', \&cached_uri_escape );

    $context->define_vmethod( 'scalar', 'cpanel_safe_html_encode_str', \&cached_html_encoder );

    return Cpanel::EncoderObj->new($class);
}

sub cached_uri_escape {
    return exists $URI_CACHE{ $_[0] } ? $URI_CACHE{ $_[0] } : ( $URI_CACHE{ $_[0] } = Cpanel::Encoder::URI::uri_encode_str( $_[0] ) );
}

sub cached_html_encoder {
    return exists $HTML_CACHE{ $_[0] } ? $HTML_CACHE{ $_[0] } : ( $HTML_CACHE{ $_[0] } = Cpanel::Encoder::Tiny::safe_html_encode_str( $_[0] ) );
}

package Cpanel::EncoderObj;

sub new {
    my ($class) = @_;
    return bless {}, $class;
}

sub safe_html_encode_str {
    my $self = shift;
    goto \&Cpanel::Encoder::Tiny::safe_html_encode_str;
}

sub base64_encode_str {
    require MIME::Base64;
    return MIME::Base64::encode_base64( $_[1], '' );
}

1;
