package Cpanel::Server::Handlers::Httpd::Check;

# cpanel - Cpanel/Server/Handlers/Httpd/Check.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::Check

=head1 SYNOPSIS

    my $is_static = is_valid_static_path( $url_path );

    reassign_appname_for_cphttpd_if_needed( $server_obj );

=head1 DESCRIPTION

This module contains verification logic used for cpsrvd’s HTTP server.

=cut

#----------------------------------------------------------------------

use Cpanel::App ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 reassign_appname_for_cphttpd_if_needed( $SERVER_OBJ )

Sets $Cpanel::App::appname to a value for a cpsrvd service
(e.g., webmail) if it’s appropriate as per the request.

$SERVER_OBJ is an instance of L<Cpanel::Server>.

=cut

# This is how we map the leftmost label in the HTTP Host header
# to the appropriate $Cpanel::App::appname.
my %HOST_PREFIX_APPNAME = (
    cpanel  => 'cpaneld',
    whm     => 'whostmgrd',
    webmail => 'webmaild',
);

sub reassign_appname_for_cphttpd_if_needed {
    my ($server_obj) = @_;

    if ( my $http_host = $server_obj->request()->get_header('host') ) {
        my $dot_at = index( $http_host, '.' );

        if ( -1 != $dot_at ) {
            my $leftmost_label = substr( $http_host, 0, $dot_at );

            if ( my $route = $HOST_PREFIX_APPNAME{$leftmost_label} ) {
                my $url_path = $server_obj->request()->get_uri();

                # grr … get_uri() doesn’t return with the leading slash.
                substr( $url_path, 0, 0, '/' ) if 0 != index( $url_path, '/' );

                if ( !is_valid_static_path($url_path) ) {
                    $Cpanel::App::appname = $route;
                }
            }
        }
    }

    return;
}

=head2 $yn = is_valid_static_path( $URL_PATH )

Returns a boolean that indicates whether this module recognizes $URL_PATH
as a path that it will try to serve up as a static URL.

Note that $URL_PATH must begin with C</>.

It would be nice if this weren’t needed, but because the cpsrvd-hosted
services aren’t themselves callable from here, we have to expose this logic
so that cpsrvd can call it to determine whether to allow this module to
serve a path or to serve it dynamically.

For example:

    https://cpanel.example.com/.well-known/pki-validation/ABCDEFG.txt

^^ We need this static path to reach this module, despite the URL
authority’s leading C<cpanel.> label.

    https://cpanel.example.com/

^^ cpsrvd will serve this dynamically because there is C<cpanel.> without
a URL path that’s recognized as a static URL.

=cut

# Only allow static documents to be served from these directories.
my @CPHTTPD_STATIC_DIRECTORIES = (
    '/.well-known',
);

sub is_valid_static_path {
    my ($url_path) = @_;

    # sanity check
    die "Invalid URL path: “$url_path”" if 0 != index( $url_path, '/' );

    my $is_static;

    for my $dir (@CPHTTPD_STATIC_DIRECTORIES) {
        next if 0 != index( $url_path, "$dir/" );

        $is_static = 1;
        last;
    }

    return $is_static || 0;
}

1;
