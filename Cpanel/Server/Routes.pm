package Cpanel::Server::Routes;

# cpanel - Cpanel/Server/Routes.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use warnings;
use strict;

=head1 NAME

Cpanel::Server::Routes

=head1 SYNOPSIS

    my $route_path = '/application/3rdparty/index.php/api/v1/command';

    my $new_path = Cpanel::Server::Routes::strip_argument_routes( $route_path, 'php' );

=head1 DESCRIPTION

Helper implementations for URL routes and arguments

=cut

=head1 SUBROUTINES

=head2 strip_argument_routes( $document, 'file_extension' )

Given a $document string with route data arugments, will return
the document leading up to (and including) the given file extension.
Anything past the given extension will be the URL arguments/route data.

Example:

application/index.php/some/custom/route

Is stripped down to:

application/index.php

--

application/index.html?search=query

Is NOT stripped.

=head2 Input

=over 2

=item L<string> Document path string

=item L<string> Expected file-type extension (i.e. php, html, cgi, py)

=back

=head2 Returns

=over 2

=item The document string up until the extension, with the route arguments stripped

=back

=cut

sub strip_argument_routes {
    my ( $document, $extension ) = @_;
    my ($embedded_document) = split /\.\Q$extension\E\K\//, $document;
    return $embedded_document;
}

1;
