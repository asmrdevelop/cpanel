package Cpanel::Server::Handlers::OpenIdConnectLink;

# cpanel - Cpanel/Server/Handlers/OpenIdConnectLink.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::App                                          ();
use Cpanel::Exception                                    ();
use Cpanel::Security::Authn::OpenIdConnect               ();
use Cpanel::Security::Authn::User::Modify                ();
use Cpanel::Server::Handlers::OpenIdConnect::ContactCopy ();

use IO::Socket::SSL::PublicSuffix ();    # required since we disable it in cpsrvd since its not needed when running as a server

use Try::Tiny;

use parent 'Cpanel::Server::Handler';

# TODO: This should really just be a sub in  Cpanel::Server::Handler::FormLogin
# once handle_form_login gets broken out
sub handler {
    my ( $self, $session_ref ) = @_;

    # openid_connect_need_link is set when doing a link request without other users, openid_connect_need_disambiguation is set when using the link account
    # from the user disambiguation/selection page when you have multiple accounts linked to one external authn account
    if ( !$session_ref->{'openid_connect_need_link'} && !$session_ref->{'openid_connect_need_disambiguation'} ) {
        die( __PACKAGE__ . ' called without needing it!' );
    }

    my $id_token_string = $session_ref->{'openid_connect_id_token'};
    if ( !length $id_token_string ) {
        die( __PACKAGE__ . ' called without OIDC token!' );
    }

    my $provider_name = $session_ref->{'openid_connect_provider'};
    if ( !length $provider_name ) {
        die( __PACKAGE__ . ' called without OIDC provider!' );
    }

    my $server_obj = $self->get_server_obj();
    my $user       = $server_obj->auth()->get_user();

    if ( $server_obj->auth()->get_demo() ) {
        die Cpanel::Exception->create('Demo accounts are not allowed to link with external authentication providers.');
    }

    my $provider_obj;

    my $provider_username = $session_ref->{'openid_connect_preferred_username'};

    $provider_obj = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $Cpanel::App::appname, $provider_name );

    my $id_token_obj = $provider_obj->get_id_token($id_token_string);

    if ( $provider_obj->can_verify() ) {

        my $signing_key = $provider_obj->get_signing_key( $id_token_obj->header()->{kid}, $id_token_obj->header()->{alg} );

        if ( !length $signing_key ) {
            die Cpanel::Exception->create('The signing key was not available on the remote server.');
        }

        $id_token_obj->key($signing_key);
        $id_token_obj->alg( $id_token_obj->header()->{alg} );

        if ( !$id_token_obj->verify() ) {
            die Cpanel::Exception->create('The [output,abbr,ID,identification] token from the remote server failed verification.');
        }
    }

    my $subject_unique_identifier = $provider_obj->get_subject_unique_identifier_from_id_token($id_token_obj);

    Cpanel::Security::Authn::User::Modify::add_authn_link_for_user(
        $user,
        'openid_connect',
        $provider_name,
        $subject_unique_identifier,
        { 'preferred_username' => $provider_username },
    );

    if ( $session_ref->{'openid_connect_email'} ) {
        Cpanel::Server::Handlers::OpenIdConnect::ContactCopy::save_user_contact_email_if_needed(
            $user,
            $session_ref->{'openid_connect_email'},
        );
    }

    return 1;
}

1;
