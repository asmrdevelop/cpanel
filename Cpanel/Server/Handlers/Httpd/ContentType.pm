package Cpanel::Server::Handlers::Httpd::ContentType;

# cpanel - Cpanel/Server/Handlers/Httpd/ContentType.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::ContentType - Detect content type

=head1 SYNOPSIS

    my $type = Cpanel::Server::Handlers::Httpd::ContentType::detect( \$content, $path );

=cut

#----------------------------------------------------------------------

use Cpanel::FileType ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $hdr_txt = detect( \$CONTENT_STR, $PATH )

Returns the detected MIME type. This first tries to detect via $CONTENT_STR,
and if that doesn’t work, it’ll look at $PATH to see if there’s an obvious
type (e.g., C<text/html>).

If a MIME type can’t be detected, this returns undef.

=cut

sub detect {
    my ( $content_sr, $path ) = @_;

    my $type = Cpanel::FileType::determine_mime_type_from_stringref($content_sr);
    return $type if $type;

    if ( substr( $path, -5 ) eq '.html' || substr( $path, -4 ) eq '.htm' ) {
        return 'text/html; charset=utf-8';
    }

    return undef;
}

1;
