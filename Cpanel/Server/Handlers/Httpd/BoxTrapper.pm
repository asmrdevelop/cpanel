package Cpanel::Server::Handlers::Httpd::BoxTrapper;

# cpanel - Cpanel/Server/Handlers/Httpd/BoxTrapper.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::BoxTrapper

=head1 SYNOPSIS

    Cpanel::Server::Handlers::Httpd::BoxTrapper::handle(
        $server_obj,    # instance of Cpanel::Server
        'johnny',       # setuid username
    );

=head1 DESCRIPTION

This is cphttpd’s handler for BoxTrapper CGI URLs.

=cut

#----------------------------------------------------------------------

use Cpanel::Server::Handlers::Httpd::CGI ();

# accessed from tests
our $_BXD_CGI_PATH;

BEGIN {
    $_BXD_CGI_PATH = '/usr/local/cpanel/cgi-sys/bxd.cgi';
}

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle_bxd( $SERVER_OBJ, $SETUID_USERNAME )

Runs F<cgi-sys/bxd.cgi> as the given $SETUID_USERNAME.

=cut

sub handle_bxd {
    my ( $server_obj, $setuid_username ) = @_;

    Cpanel::Server::Handlers::Httpd::CGI::handle(
        server_obj      => $server_obj,
        script_filename => $_BXD_CGI_PATH,
        script_name     => "/cgi-sys/bxd.cgi",
        setuid          => $setuid_username,
    );

    return;
}

1;
