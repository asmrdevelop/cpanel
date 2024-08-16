package Cpanel::Server::Handlers::Httpd::Mailman;

# cpanel - Cpanel/Server/Handlers/Httpd/Mailman.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Httpd::Mailman

=head1 SYNOPSIS

    Cpanel::Server::Handlers::Httpd::Mailman::handle(
        $server_obj,    # instance of Cpanel::Server
        '/url/path',
    );

=head1 DESCRIPTION

This is cphttpd’s handler for GNU Mailman.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception                       ();
use Cpanel::Server::Handlers::Httpd::SetUid ();

# These are referenced from tests.
use constant {
    _MAILMAN_CGI_DIR => '/usr/local/cpanel/3rdparty/mailman/cgi-bin',
    _ARCHIVES_DIR    => '/usr/local/cpanel/3rdparty/mailman/archives/public',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle( $SERVER_OBJ, $HTTP_HOST, $URL_PATH )

This handler implements access to public archives and to the
Mailman CGI scripts. $SERVER_OBJ is a L<Cpanel::Server> instance, $HTTP_HOST
is the C<Host> HTTP header, and $URL_PATH is the path given in the 1st line
of the HTTP request.

Nothing is returned.

=cut

sub handle {
    my ( $server_obj, $http_host, $url_path ) = @_;

    if ( 0 == index( $url_path, '/pipermail/' ) ) {
        substr( $url_path, 0, 11, '/mailman/archives/' );
    }

    my $cmd = _get_mailman_command($url_path);

    my $setuid_username = Cpanel::Server::Handlers::Httpd::SetUid::determine_setuid_user_by_host($http_host);

    if ( 0 == index( $cmd, 'archives/' ) ) {
        _handle_archives_request( $server_obj, $setuid_username, $cmd );
    }
    else {
        require Cpanel::Server::Handlers::Httpd::CGI;

        # Mailman CGIs need to run as the mailman user; however,
        # they are setuid to the mailman user and so can be exec()’ed
        # as the HTTP Host’s associated user.

        Cpanel::Server::Handlers::Httpd::CGI::handle(
            server_obj      => $server_obj,
            script_filename => _MAILMAN_CGI_DIR() . "/$cmd",
            script_name     => "/mailman/$cmd",
            setuid          => $setuid_username,
        );
    }

    return;
}

sub _handle_archives_request {
    my ( $server_obj, $setuid_username, $cmd ) = @_;

    # The first 9 characters are “archives/”.
    substr( $cmd, 0, 9 ) = q<>;

    my @args = (
        server_obj => $server_obj,
        path       => _ARCHIVES_DIR() . "/$cmd",
        setuid     => $setuid_username,

        # NB: We let Static.pm detect the MIME type.
    );

    my $func;
    if ( '/' eq substr( $cmd, -1 ) ) {
        $func = 'handle_directory';
        push @args, dirindex => ['index.html'];
    }
    else {
        $func = 'handle';
    }

    require Cpanel::Server::Handlers::Httpd::Static;
    Cpanel::Server::Handlers::Httpd::Static->can($func)->(@args);

    return;
}

sub _get_mailman_command {
    my ($url_path) = @_;

    # The first 9 characters are “/mailman/”.
    my $cmd = substr( $url_path, 9 );

    if ( 0 != index( $cmd, 'archives/' ) ) {
        my $slash_at = index( $cmd, '/' );

        # The first piece of the path after “/mailman/” is the command.
        if ( -1 != $slash_at ) {
            substr( $cmd, $slash_at ) = q<>;

            if ( !length($cmd) ) {
                die Cpanel::Exception::create('cpsrvd::NotFound');
            }
        }
    }

    return $cmd;
}

1;
