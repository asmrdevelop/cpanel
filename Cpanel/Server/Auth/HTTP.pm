package Cpanel::Server::Auth::HTTP;

# cpanel - Cpanel/Server/Auth/HTTP.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Server::Auth::HTTP

=head1 DESCRIPTION

This module contains some of cpsrvd’s logic for
HTTP authentication (i.e., the C<Authorization> header).

=cut

#----------------------------------------------------------------------

use Cpanel::Exception                ();
use Cpanel::Validate::Username::Core ();

# Ideally, eventually, this will be internal-only.
# But for now it’s consumed externally.
use constant TOKEN_DOCUMENT_WHITELIST_WHM => (
    './websocket/MysqlDump',
    './websocket/CommandStream',
    './websocket/TarRestore',
    './websocket/TarBackup',
);

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 handle_cpanel_api_token( $SERVER_OBJ, $HEADER_DETAIL )

This alters the passed-in $SERVER_OBJ (instance of L<Cpanel::Server>)
as well as C<%ENV> according to the given “detail”—i.e., the portion
of the C<Authorization> header that follows the service name (C<cpanel>
in this case) and space.

(Example: if the C<Authorization> header’s value is
C<cpanel foo:bar>, then C<foo:bar> is the $HEADER_DETAIL.)

This can also call C<badpass()> on the server object if there is a
problem that warrants immediate rejection of the request.

=cut

sub handle_cpanel_api_token {
    my ( $server_obj, $header_detail ) = @_;

    _handle( 'token', $server_obj, $header_detail );

    my $doc = $server_obj->request()->get_document();

    # UAPI
    my $doc_ok_yn = ( 0 == rindex( $doc, './execute/', 0 ) );

    # API 2 or API 1
    # We aren’t able to filter API 1 here because at this point
    # we only know the request path, and the distinction between
    # API 1 and API 2 can be sent in the request payload (i.e.,
    # the POST) as well as the URL query. So we have to filter it
    # later, in the actual API call handler.
    $doc_ok_yn ||= ( $doc eq './json-api/cpanel' );

    # Allow MySQL dumps.
    $doc_ok_yn ||= ( $doc eq './websocket/MysqlDump' );

    # Allow use of rsync-streamed homedir backups
    # and dsync-streamed mail transfers.
    $doc_ok_yn ||= ( $doc eq './cpxfer/acctxferrsync' );
    $doc_ok_yn ||= ( $doc eq './cpxfer/dsync' );

    # WP Toolkit
    $doc_ok_yn ||= ( index( $doc, './3rdparty/wpt/index.php' ) == 0 );

    if ( !$doc_ok_yn ) {
        die Cpanel::Exception::create_raw( 'cpsrvd::Forbidden', 'Token authentication allows access to UAPI or API 2 calls only.' );
    }

    return;
}

#----------------------------------------------------------------------

=head2 handle_whm_api_token( $SERVER_OBJ, $HEADER_DETAIL )

Similar to C<handle_cpanel_api_token()>, but for WHM requests.

=cut

sub handle_whm_api_token {
    my ( $server_obj, $header_detail ) = @_;

    # WHM sets “whm” as the auth type because of the possibility
    # that the given token might be a legacy access hash.
    # Later on in cpsrvd, when we discern the difference, it’ll
    # be set to “token” if appropriate.
    return _handle( 'whm', $server_obj, $header_detail );
}

#----------------------------------------------------------------------

sub _handle {
    my ( $auth_type, $server_obj, $header_detail ) = @_;

    my ( $username, $token_or_hash ) = split( /:/, $header_detail, 2 );

    if ( !length $token_or_hash ) {
        $server_obj->badpass( 'faillog' => 'No token given.' );
    }

    unless ( Cpanel::Validate::Username::Core::is_valid_system_username($username) ) {
        $server_obj->badpass( 'faillog' => 'user name not provided or invalid user' );
    }

    # Always send HTTP error codes with token authentication
    if ( $server_obj->request()->get_error_output_type() eq 'normal' ) {
        $server_obj->request()->set_error_output_type('dnsadmin');
    }

    $server_obj->auth()->set_user($username);
    $server_obj->auth()->set_http_auth_token($token_or_hash);
    $server_obj->auth()->set_auth_type($auth_type);

    return;
}

1;
