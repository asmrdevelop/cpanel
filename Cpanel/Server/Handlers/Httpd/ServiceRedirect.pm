package Cpanel::Server::Handlers::Httpd::ServiceRedirect;

# cpanel - Cpanel/Server/Handlers/Httpd/ServiceRedirect.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::ServiceRedirect

=head1 SYNOPSIS

    Cpanel::Server::Handlers::Httpd::ServiceRedirect::redirect_to_cpanel(
        $server_obj,
    );

    Cpanel::Server::Handlers::Httpd::ServiceRedirect::redirect_to_whm(
        $server_obj,
    );

    Cpanel::Server::Handlers::Httpd::ServiceRedirect::redirect_to_webmail(
        $server_obj,
    );

=head1 DESCRIPTION

This module implements cphttpd’s HTTP 3xx redirections to the relevant
cpsrvd services.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception                    ();
use Cpanel::Server::Handlers::Httpd::CGI ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 redirect_to_cpanel( $SERVER_OBJ )

Redirects to cPanel. $SERVER_OBJ is an instance of L<Cpanel::Server>.

=cut

sub redirect_to_cpanel {
    my ($server_obj) = @_;

    Cpanel::Server::Handlers::Httpd::CGI::handle(
        server_obj      => $server_obj,
        script_filename => '/usr/local/cpanel/cgi-sys/redirect.cgi',
        script_name     => '/cpanel',
        setuid          => 'nobody',
    );

    return;
}

#----------------------------------------------------------------------

=head2 redirect_to_whm( $SERVER_OBJ )

Like C<redirect_to_cpanel()> but for WHM.

=cut

sub redirect_to_whm {
    my ($server_obj) = @_;

    Cpanel::Server::Handlers::Httpd::CGI::handle(
        server_obj      => $server_obj,
        script_filename => '/usr/local/cpanel/cgi-sys/whmredirect.cgi',
        script_name     => '/whm',
        setuid          => 'nobody',
    );

    return;
}

#----------------------------------------------------------------------

=head2 redirect_to_webmail( $SERVER_OBJ )

Like C<redirect_to_cpanel()> but for Webmail. This throws.
L<Cpanel::Exception::cpsrvd::NotFound> if the Webmail role is disabled.

=cut

sub redirect_to_webmail {
    my ($server_obj) = @_;

    require Cpanel::Server::Type::Role::Webmail;

    if ( !Cpanel::Server::Type::Role::Webmail->is_enabled() ) {
        die Cpanel::Exception::create('cpsrvd::NotFound');
    }

    Cpanel::Server::Handlers::Httpd::CGI::handle(
        server_obj      => $server_obj,
        script_filename => '/usr/local/cpanel/cgi-sys/wredirect.cgi',
        script_name     => '/webmail',
        setuid          => 'nobody',
    );

    return;
}

1;
