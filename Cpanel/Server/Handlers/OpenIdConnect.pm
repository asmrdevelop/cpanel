package Cpanel::Server::Handlers::OpenIdConnect;

# cpanel - Cpanel/Server/Handlers/OpenIdConnect.pm Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::AcctUtils::Lookup::Webmail                   ();
use Cpanel::PwCache                                      ();
use Cpanel::App                                          ();
use Cpanel::HTTP::QueryString                            ();
use Cpanel::AdminBin::Serializer                         ();
use Cpanel::LoadModule                                   ();
use Cpanel::Login::Url                                   ();
use Cpanel::Reseller                                     ();
use Cpanel::Security::Authn::OpenIdConnect               ();
use Cpanel::Security::Authn::User                        ();
use Cpanel::Security::Authn::Config                      ();
use Cpanel::Server::Handlers::OpenIdConnect::ContactCopy ();
use Cpanel::Session::Load                                ();
use Cpanel::Session::Modify                              ();
use Cpanel::Services::Ports                              ();
use Cpanel::SSL::Domain                                  ();

use IO::Socket::SSL::PublicSuffix ();    # required since we disable it in cpsrvd since its not needed when running as a server
use Try::Tiny;

my $DEFAULT_TIMEOUT = 500;

use parent 'Cpanel::Server::Handler';

sub handler {
    my ($self) = @_;

    my $server_obj = $self->get_server_obj();
    my $document   = $server_obj->request()->get_document();

    $self->_check_host_and_redirect_if_not_best_ssl_domain();

    # start OpenID Connect interaction
    # cf. http://openid.net/specs/openid-connect-core-1_0.html#CodeFlowSteps
    if ( $document =~ m{^\.?/openid_connect/([^/]*)} ) {
        $self->_init_openid_connect_provider($1);
        $self->_openid_connect();
    }

    # Callback from remote server to provide authorization code to retrieve the access token
    # cf. http://openid.net/specs/openid-connect-core-1_0.html#CodeFlowSteps
    elsif ( $document =~ m{^\.?/openid_connect_callback/([^/]*)} ) {
        $self->_init_openid_connect_provider($1);
        $self->_check_service_and_redirect_to_correct_service();
        $self->_openid_connect_callback();
    }
    return 1;
}

sub _check_service_and_redirect_to_correct_service {
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    my $query_hr = $self->_get_query_hr();
    my $state    = $self->_get_provider_obj()->deserialize_state( $query_hr->{'state'} );

    if ( $state && $state->{'service'} ne $Cpanel::App::appname ) {
        my $port_service_name = $state->{'service'};
        $port_service_name =~ s{d$}{s}g;    # change cpaneld => cpanels
        my $redirect_port = $Cpanel::Services::Ports::SERVICE{$port_service_name};
        die "The service “$state->{'service'}” is not a known service" if !$redirect_port;
        my $ssl_domain = Cpanel::SSL::Domain::get_best_ssldomain_for_service('cpanel');
        $server_obj->redirect_request("https://$ssl_domain:$redirect_port/");
    }
    return 1;
}

sub _check_host_and_redirect_if_not_best_ssl_domain {
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    my $ssl_domain = Cpanel::SSL::Domain::get_best_ssldomain_for_service('cpanel');
    if ( $ssl_domain ne $ENV{'HTTP_HOST'} ) {
        my $service     = $Cpanel::App::appname =~ s/d$/s/r;
        my $server_port = $Cpanel::Services::Ports::SERVICE{$service} || $ENV{'SERVER_PORT'} || die "The SERVER_PORT was not set";
        $server_obj->redirect_request("https://$ssl_domain:$server_port/");
    }

    return;
}

sub _init_openid_connect_provider {
    my ( $self, $unvalidated_provider_name ) = @_;

    try {
        local $SIG{__DIE__};    # Make sure the try/catch handles the exception
        if ( !grep { $_ eq $Cpanel::App::appname } @Cpanel::Security::Authn::Config::ALLOWED_SERVICES ) {
            die "$Cpanel::App::appname does not support openid connect authentication";
        }

        $self->{'_provider_obj'}  = Cpanel::Security::Authn::OpenIdConnect::get_openid_provider( $Cpanel::App::appname, $unvalidated_provider_name );
        $self->{'_provider_name'} = $self->{'_provider_obj'}->get_provider_name();

    }
    catch {
        require Cpanel::Exception;
        my $error_string = "openid connect: '$Cpanel::App::appname' provider '$unvalidated_provider_name' encountered an error: " . Cpanel::Exception::get_string($_);
        $self->warn_in_error_log($error_string);
        $self->get_server_obj()->send_to_login_page( 'faillog' => $error_string, 'preserve_token' => 1 );
    };

    return 1;
}

sub _openid_connect {
    my ($self) = @_;
    my $server_obj = $self->get_server_obj();

    my $session_from_cookie = $self->_get_or_create_session_if_expired_or_non_existent();
    my $query_hr            = $self->_get_query_hr();
    my $login_url;

    my $provider_obj = $self->_get_provider_obj();
    my $session_mod  = Cpanel::Session::Modify->new($session_from_cookie);
    my $session_ref  = $session_mod->can('get_data') ? $session_mod->get_data() : $session_mod->{'_data'};

    $session_mod->set(
        'openid_connect_state',
        Cpanel::AdminBin::Serializer::Dump(
            {
                'goto_uri'           => $query_hr->{'goto_uri'},
                'goto_app'           => $query_hr->{'goto_app'},
                'token_denied'       => $query_hr->{'token_denied'},
                'parameterized_form' => $query_hr->{'parameterized_form'},
                'action'             => $query_hr->{'action'} || 'login',
                ( $query_hr->{'token_denied'} && length $query_hr->{'user'} ? ( 'user' => $query_hr->{'user'} ) : () ),
            }
        )
    );
    $session_mod->save();

    try {
        local $SIG{__DIE__};    # Make sure the try/catch handles the exception
        $login_url = $provider_obj->start_authorize(
            {
                'service'                   => $Cpanel::App::appname,
                'external_validation_token' => $session_ref->{'external_validation_token'},
            },
        );
    }
    catch {
        require Cpanel::Exception;
        my $provider_name = $provider_obj->get_provider_name();
        my $error_string  = "openid connect: '$Cpanel::App::appname' provider '$provider_name' encountered an error: " . Cpanel::Exception::get_string($_);
        $self->warn_in_error_log($error_string);
        $self->_send_server_to_login_page(
            'faillog'        => $error_string,
            msg_code         => 'openid_communication_no_login',
            oidc_failed      => $provider_name,
            oidc_error       => $error_string,
            'preserve_token' => 1,
        );
    };

    return $server_obj->docmoved( $login_url, scalar $server_obj->get_login_cookie_http_header($session_from_cookie), 302 );
}

sub _send_server_to_login_page {
    my ( $self, @opts ) = @_;

    return $self->get_server_obj()->send_to_login_page(
        @opts,
        openid_provider_display_name => scalar $self->{'_provider_obj'}->get_provider_display_name(),
        openid_provider_link         => $self->{'_provider_obj'}->get_display_configuration($Cpanel::App::appname)->{'link'} . '?' . Cpanel::HTTP::QueryString::make_query_string( goto_uri => '/' ),
    );
}

sub _get_query_hr {
    return Cpanel::HTTP::QueryString::parse_query_string_sr( \$ENV{'QUERY_STRING'} );
}

sub _openid_connect_callback {
    my ($self) = @_;

    my $provider_name = $self->_get_provider_name();
    my $query_hr      = $self->_get_query_hr();
    my $server_obj    = $self->get_server_obj();

    my $callback_data = $self->_extract_callback_data();

    my ( $access_token, $id_token, $subject_unique_identifier, $state, $access_token_expiry ) = @{$callback_data}{qw( access_token_obj id_token_obj subject_unique_identifier state access_token_expiry )};

    my @users = grep { _filter_user_by_calling_context($_) } Cpanel::Security::Authn::User::get_users_by_authn_provider_and_link(
        'openid_connect',
        $provider_name,
        $subject_unique_identifier,
    );

    if ( time() >= $access_token_expiry ) {
        $self->_send_server_to_login_page(
            faillog        => "openid connect: '$Cpanel::App::appname' provider '$provider_name' access token expired",
            msg_code       => 'openid_access_token_expired',
            oidc_failed    => $provider_name,
            preserve_token => 1,
        );
    }

    my $action = $state->{'action'} || 'login';

    if ( $action eq 'login' ) {
        if (@users) {
            if ( scalar @users == 1 ) {
                $self->_handle_openid_connect_user_selection( user => $users[0], state => $state, id_token_obj => $id_token, access_token_obj => $access_token, access_token_expiry => $access_token_expiry );
                return;    # Won't get here normally, but we do in the tests
            }
            elsif ( length $query_hr->{'openid_user_selection'} && grep { $_ eq $query_hr->{'openid_user_selection'} } @users ) {
                $self->_handle_openid_connect_user_selection( user => $query_hr->{'openid_user_selection'}, state => $state, id_token_obj => $id_token, access_token_obj => $access_token, access_token_expiry => $access_token_expiry );
                return;    # Won't get here normally, but we do in the tests
            }
            elsif ( $state->{'token_denied'} && length $state->{'user'} && grep { $_ eq $state->{'user'} } @users ) {
                $self->_handle_openid_connect_user_selection( user => $state->{'user'}, state => $state, id_token_obj => $id_token, access_token_obj => $access_token, access_token_expiry => $access_token_expiry );
                return;    # Won't get here normally, but we do in the tests
            }
            else {
                $self->_handle_openid_need_to_select_user( linked_users => \@users, state => $state, id_token_obj => $id_token, access_token_obj => $access_token, access_token_expiry => $access_token_expiry );
                return;    # Won't get here normally, but we do in the tests
            }
        }
    }

    return $self->_handle_openid_connect_link_request(
        'access_token_obj'    => $access_token,
        'id_token_obj'        => $id_token,
        'existing_link_count' => scalar @users,
        'goto_app'            => $state->{'goto_app'},
        'goto_uri'            => $state->{'goto_uri'},
        'access_token_expiry' => $access_token_expiry
    );
}

sub _extract_callback_data {
    my ($self) = @_;

    my $server_obj    = $self->get_server_obj();
    my $provider_name = $self->_get_provider_name();
    my $provider_obj  = $self->_get_provider_obj();
    my $query_hr      = $self->_get_query_hr();

    my ( $access_token, $id_token, $subject_unique_identifier, $state, $access_token_expiry );

    my $session_from_cookie = $server_obj->get_current_session();
    my $session_ref         = Cpanel::Session::Load::loadSession($session_from_cookie);

    $self->_execute_remote_openid_call_with_exception_handler(
        sub {

            # User selection/disambiguation
            if ( $session_ref->{'openid_connect_need_disambiguation'} ) {
                $self->_validate_session_for_disambiguation($session_ref);

                $state = Cpanel::AdminBin::Serializer::Load( $session_ref->{'openid_connect_state'} );    # Cpanel::AdminBin::Serializer is UTF-8 "safe"

                Cpanel::LoadModule::load_perl_module('OIDC::Lite::Client::Token');

                $access_token = OIDC::Lite::Client::Token->new(
                    {
                        ( map { $_ => $session_ref->{"openid_connect_$_"}       || '' } qw( access_token refresh_token id_token ) ),
                        ( map { $_ => $session_ref->{"openid_connect_token_$_"} || '' } qw( scope expires_in ) )
                    }
                );

                $id_token = $provider_obj->get_id_token($access_token);

                # Just going to the log, doesn't need to be localized
                die Cpanel::Exception::create_raw( 'InvalidSession', 'The OpenID Connect access token found in the session does not contain a valid ID Token.' ) if !$id_token;

                $subject_unique_identifier = $provider_obj->get_subject_unique_identifier_from_auth_token($access_token);

                $access_token_expiry = $session_ref->{'openid_connect_token_expiry'};
            }
            else {    # Everything else
                $self->_validate_openid_response($query_hr);
                $access_token = $provider_obj->callback( $query_hr->{'code'} );
                $id_token     = $provider_obj->get_id_token($access_token);

                # This is only going to the log, no need to localize
                die Cpanel::Exception::create_raw( 'Authz::MissingIdToken', 'The remote server did not send back an ID Token in the callback.' ) if !$id_token;

                $subject_unique_identifier = $provider_obj->get_subject_unique_identifier_from_auth_token($access_token);

                $state                              = defined $session_ref->{'openid_connect_state'} ? Cpanel::AdminBin::Serializer::Load( $session_ref->{'openid_connect_state'} ) : {};
                $state->{service}                   = $Cpanel::App::appname;                                                                                                                # validated in _check_service_and_redirect_to_correct_service()
                $state->{external_validation_token} = $session_ref->{external_validation_token};                                                                                            # validated in _validate_openid_response()

                $access_token_expiry = time() + 1 + ( $access_token->expires_in() || $Cpanel::Security::Authn::Config::DEFAULT_ACCESS_TOKEN_EXPIRES_IN );
            }
        }
    );
    return {
        access_token_obj          => $access_token,
        id_token_obj              => $id_token,
        subject_unique_identifier => $subject_unique_identifier,
        state                     => $state,
        access_token_expiry       => $access_token_expiry,
    };
}

# User selection/disambiguation
sub _validate_session_for_disambiguation {
    my ( $self, $session_ref ) = @_;

    my $request_provider_name = $self->_get_provider_name();

    # These error messages will just end up in the log, so no need to localize here
    if ( $request_provider_name ne $session_ref->{'openid_connect_provider'} ) {
        die Cpanel::Exception::create_raw( 'InvalidSession', "The provider found in the session “$session_ref->{'openid_connect_provider'}” does not match the provider from the request “$request_provider_name”" );
    }

    if ( !$session_ref->{'openid_connect_state'} ) {
        die Cpanel::Exception::create_raw( 'InvalidSession', "The session does not contain the OpenID Connect state." );
    }

    if ( !$session_ref->{'openid_connect_access_token'} ) {
        die Cpanel::Exception::create_raw( 'InvalidSession', 'The session does not contain the OpenID Connect access token.' );
    }

    if ( !$session_ref->{'openid_connect_token_expiry'} ) {
        die Cpanel::Exception::create_raw( 'InvalidSession', 'The session does not contain the OpenID Connect access token expiry.' );
    }

    return 1;
}

sub _handle_openid_connect_link_request {
    my ( $self, %OPTS ) = @_;

    # $existing_link_count will always be 0 currently, we use the user disambiguation/selection screen to add new linked accounts if there are more than 0.
    my ( $access_token, $id_token, $existing_link_count, $goto_app, $goto_uri, $access_token_expiry ) = @OPTS{qw( access_token_obj id_token_obj existing_link_count goto_app goto_uri access_token_expiry)};

    my $provider_obj = $self->_get_provider_obj();
    my $server_obj   = $self->get_server_obj();

    my $user_info_payload = $self->_get_user_info_trapped($access_token);

    my $preferred_username = $provider_obj->get_human_readable_account_identifier_from_user_info($user_info_payload);

    my $session_from_cookie = $server_obj->get_current_session();

    my $session_mod       = Cpanel::Session::Modify->new($session_from_cookie);
    my $session_ref       = $session_mod->can('get_data')                                                                                              ? $session_mod->get_data() : $session_mod->{'_data'};
    my $already_logged_in = ( $session_ref->{'successful_internal_auth_with_timestamp'} || $session_ref->{'successful_external_auth_with_timestamp'} ) ? 1                        : 0;

    my $email = $self->_extract_email_from_userinfo_payload($user_info_payload);

    $session_mod->set( 'openid_connect_id_token',           $id_token->token_string() );
    $session_mod->set( 'openid_connect_provider',           $self->_get_provider_name() );
    $session_mod->set( 'openid_connect_preferred_username', $preferred_username );
    $session_mod->set( 'openid_connect_email',              $email );
    $session_mod->set( 'openid_connect_need_link',          1 );
    $session_mod->set( 'needs_auth',                        1 ) unless $already_logged_in;
    $session_mod->set( 'openid_connect_token_expiry',       $access_token_expiry );

    $session_mod->save();

    #Already logged in, just do the link rather than
    #making the user log in again.
    if ($already_logged_in) {
        my $security_token = $session_ref->{'cp_security_token'};

        my $service = $Cpanel::App::appname;
        $service =~ s{d$}{};

        my $xferurl = Cpanel::Login::Url::generate_login_url(
            $service,
            trailing_separator_supplied_by_caller => 1,
        );
        $xferurl .= "$security_token/login/?";
        $xferurl .= Cpanel::HTTP::QueryString::make_query_string(
            {
                session  => $session_from_cookie,
                goto_app => $goto_app,
                goto_uri => $goto_uri,
            }
        );

        return $server_obj->docmoved( $xferurl, q{}, 307 );
    }

    return $server_obj->send_to_login_page(
        'msg_code'            => 'link_account',
        'existing_link_count' => $existing_link_count,
        'link_account'        => 1,
        'keep_session'        => 1,
        'user_info_payload'   => $user_info_payload,
        'preferred_username'  => $preferred_username,
        ( length $goto_app ? ( 'goto_app' => $goto_app, ) : () ),
        ( length $goto_uri ? ( 'goto_uri' => $goto_uri, ) : () ),
    );
}

sub _handle_openid_need_to_select_user {
    my ( $self, %OPTS ) = @_;

    my ( $access_token, $id_token, $linked_users, $state, $access_token_expiry ) = @OPTS{qw( access_token_obj id_token_obj linked_users state access_token_expiry )};

    my $provider_obj = $self->_get_provider_obj();
    my $server_obj   = $self->get_server_obj();

    my $user_info_payload = $self->_get_user_info_trapped($access_token);

    # This should always prefer the email
    my $preferred_username = $provider_obj->get_human_readable_account_identifier_from_user_info($user_info_payload);

    my $session_from_cookie = $server_obj->get_current_session();
    my $email               = $self->_extract_email_from_userinfo_payload($user_info_payload);

    my $session_mod = Cpanel::Session::Modify->new($session_from_cookie);
    $session_mod->set( 'openid_connect_provider',            scalar $self->_get_provider_name() );
    $session_mod->set( 'openid_connect_id_token',            scalar $id_token->token_string() );
    $session_mod->set( 'openid_connect_preferred_username',  $preferred_username );
    $session_mod->set( 'openid_connect_email',               $email );
    $session_mod->set( 'openid_connect_need_disambiguation', 1 );
    $session_mod->set( 'openid_connect_state',               Cpanel::AdminBin::Serializer::Dump($state) );
    $session_mod->set( 'openid_connect_access_token',        scalar $access_token->access_token() );
    $session_mod->set( 'openid_connect_token_expires_in',    scalar $access_token->expires_in() );
    $session_mod->set( 'openid_connect_token_scope',         scalar $access_token->scope() );
    $session_mod->set( 'openid_connect_refresh_token',       scalar $access_token->refresh_token() );
    $session_mod->set( 'openid_connect_token_expiry',        $access_token_expiry );
    $session_mod->save();

    my $linked_users_;
    for my $user ( @{$linked_users} ) {
        my $md5_hex = _generate_md5_for_gravatar($user);
        push @{$linked_users_},
          {
            'username' => $user,
            'md5_hex'  => $md5_hex
          };
    }

    return $server_obj->send_to_login_page(
        'msg_code'                     => 'user_selection',
        'keep_session'                 => 1,
        'linked_users'                 => $linked_users_,
        'preferred_username'           => $preferred_username,
        'openid_provider_display_name' => scalar $provider_obj->get_provider_display_name(),
        'user_info_payload'            => $user_info_payload,
        'link_account'                 => 1,                                                   #this hides the ext auth login buttons
        'notice_style'                 => 'info-notice'
    );
}

sub _generate_md5_for_gravatar {
    my ($username) = @_;
    Cpanel::LoadModule::load_perl_module('Digest::MD5');
    return Digest::MD5::md5_hex( $username || 'anonymous@cpanel.net' );
}

sub _handle_openid_connect_user_selection {
    my ( $self, %OPTS ) = @_;

    my $server_obj    = $self->get_server_obj();
    my $provider_name = $self->_get_provider_name();

    my ( $user, $access_token, $id_token, $state, $access_token_expiry ) = @OPTS{qw( user access_token_obj id_token_obj state access_token_expiry)};

    if ( $user eq 'root' && $Cpanel::App::appname ne 'whostmgrd' ) {
        my $error_string = "openid connect: '$Cpanel::App::appname' provider '$provider_name' does not support logging in as root";
        $server_obj->send_to_login_page( 'faillog' => $error_string, 'preserve_token' => 1, 'msg_code' => 'invalid_login' );
    }
    elsif ( $Cpanel::App::appname eq 'webmaild' ) {
        require Cpanel::AcctUtils::Lookup::MailUser;
        my $mail_user_lookup = Cpanel::AcctUtils::Lookup::MailUser::lookup_mail_user( $user, q{} );
        if ( !$mail_user_lookup->{'status'} ) {
            my $error_string = "openid connect: '$Cpanel::App::appname' lookup of '$user' failed: $mail_user_lookup->{'statusmsg'}";
            $server_obj->send_to_login_page( 'faillog' => $error_string, 'preserve_token' => 1, 'msg_code' => 'invalid_login' );
        }
        my $mail_user_info = $mail_user_lookup->{'user_info'};
        if ( $mail_user_info->{'shadow'}->{'user'} =~ m{^!} ) {
            my $error_string = "openid connect: '$Cpanel::App::appname' the user '$user' is suspended";
            $server_obj->send_to_login_page( 'faillog' => $error_string, 'preserve_token' => 1, 'msg_code' => 'invalid_login' );
        }
    }

    # Will redirect and kill connection
    return $self->_handle_openid_connect_login_success_for_user(
        'access_token_obj'    => $access_token,
        'id_token_obj'        => $id_token,
        'user'                => scalar Cpanel::AcctUtils::Lookup::Webmail::normalize_webmail_user($user),
        'goto_app'            => $state->{'goto_app'},
        'goto_uri'            => $state->{'goto_uri'},
        'parameterized_form'  => $state->{'parameterized_form'},
        'token_denied'        => $state->{'token_denied'},
        'access_token_expiry' => $access_token_expiry,
    );
}

sub _handle_openid_connect_login_success_for_user {
    my ( $self, %OPTS ) = @_;

    my ( $user, $access_token, $id_token, $access_token_expiry ) = @OPTS{qw( user access_token_obj id_token_obj access_token_expiry )};
    my $server_obj = $self->get_server_obj();

    $self->_load_user_info_and_update_cpuser_contact_email_if_needed(
        $user,
        $access_token,
    );

    my $session_from_cookie       = $server_obj->get_current_session();
    my $user_provided_session_ref = Cpanel::Session::Load::loadSession($session_from_cookie);

    # Try to preserve the security token so we can give it back
    # to them if they have a successful cookie login again
    #
    # Note: We cannot do this for http basic auth because the login
    # is passive and thus not xsrf safe
    my %security_token_options;
    if ( $user_provided_session_ref->{'cp_security_token'} && $user_provided_session_ref->{'user'} && $user_provided_session_ref->{'user'} eq $user ) {
        %security_token_options = ( 'cp_security_token' => $user_provided_session_ref->{'cp_security_token'} );
    }

    my $goto_uri = $OPTS{'goto_uri'} || '';

    # We've logged back in from the token denied page, but we chose a different openid connect authn.
    # This resulted in us logging in as a different user. So, let's default back to the main login page
    if ( $OPTS{'token_denied'} && $user_provided_session_ref->{'user'} && $user_provided_session_ref->{'user'} ne $user ) {
        $goto_uri = q{};
    }

    # Always start a new session after a login success
    require Cpanel::AcctUtils::Lookup;
    my $system_user = Cpanel::AcctUtils::Lookup::get_system_user($user);

    $server_obj->killsession( undef, 'openid_loginsuccess' );
    $server_obj->auth()->set_user($user);
    $server_obj->auth()->set_homedir( Cpanel::PwCache::gethomedir($system_user) );
    if ( $Cpanel::App::appname eq 'webmaild' ) {
        $server_obj->auth()->set_webmailowner($system_user);
    }
    my $owner = $user eq 'root' ? 'root' : $server_obj->auth()->get_owner() or die "owner is not set in the request";

    my $randsession = $server_obj->newsession(
        'user'  => $user,
        'owner' => $owner,
        %security_token_options,
        'successful_external_auth_with_timestamp' => time(),
        'openid_connect_id_token'                 => scalar $id_token->token_string(),
        'openid_connect_access_token'             => scalar $access_token->access_token(),
        'openid_connect_provider'                 => scalar $self->_get_provider_name(),
        'openid_connect_token_expiry'             => $access_token_expiry,
        'origin'                                  => {
            'method'  => 'handle_openid_connect_login_success',
            'path'    => 'openid_connect',
            'creator' => $user,
        },
    );

    # For tests
    $server_obj->auth->set_session_cookie($randsession);

    if ( length $OPTS{'goto_app'} ) {
        $goto_uri = $server_obj->calculate_login_goto_uri_from_goto_app( $user, $OPTS{'goto_app'} );
    }

    $goto_uri = $server_obj->calculate_login_goto_uri( ( split( m{\?}, $goto_uri ) )[0] );

    if ( $OPTS{'token_denied'} ) {
        my $login_cookie_http_header = $server_obj->get_login_cookie_http_header($randsession);
        $server_obj->do_token_passthrough( $goto_uri, $OPTS{'parameterized_form'}, $login_cookie_http_header );
    }
    else {
        $server_obj->docmoved( $goto_uri, $server_obj->get_login_cookie_http_header($randsession), 302 );
    }
    $server_obj->connection()->killconnection('did openid connect login');

    return;
}

sub _validate_openid_response {
    my ( $self, $query_hr ) = @_;

    if ( $query_hr->{'error'} ) {

        # This is only going to the log, no need to localize
        die Cpanel::Exception::create_raw(
            'Authz::CallbackFailure',
            "callback failure ($query_hr->{'error'}): " . $query_hr->{'error_description'},
            { map { $_ => $query_hr->{$_} } qw(error  error_description) },
        );
    }
    elsif ( !length $query_hr->{'code'} ) {    # one time code
                                               # This is only going to the log, no need to localize
        die Cpanel::Exception::create_raw( 'Authz::MissingCode', "invalid callback: missing code" );
    }
    elsif ( !length $query_hr->{'state'} ) {

        # This is only going to the log, no need to localize
        die Cpanel::Exception::create_raw( 'Authz::MissingState', "invalid callback: missing state" );
    }

    my $server_obj                                       = $self->get_server_obj();
    my $state                                            = $self->_get_provider_obj()->deserialize_state( $query_hr->{'state'} );
    my $external_validation_token_returned_from_provider = $state->{'external_validation_token'};
    if ( my $user_provided_session_ref = $server_obj->get_current_session_ref_if_exists_and_active() ) {
        if ( $user_provided_session_ref->{'external_validation_token'} && $user_provided_session_ref->{'external_validation_token'} eq $external_validation_token_returned_from_provider ) {
            return 1;
        }
        else {
            # This is only going to the log, no need to localize
            die Cpanel::Exception::create_raw( 'Authz::InvalidExternalValidationToken', "The external validation token ($external_validation_token_returned_from_provider) from the external authentication provider did not match the one contained in the session ($user_provided_session_ref->{'external_validation_token'})." );
        }
    }
    else {
        my $session_from_cookie = $server_obj->get_current_session() || q{};

        # This is only going to the log, no need to localize
        die Cpanel::Exception::create_raw( 'SessionExpired', "The session “$session_from_cookie” is missing or expired." );
    }
}

sub _get_msg_code_from_callback_exception {
    my ($exception) = @_;

    return undef if !try { $exception->isa('Cpanel::Exception') };

    if ( try { $exception->isa('Cpanel::Exception::Authz::CallbackFailure') } ) {
        my $error_code = $exception->get('error') || q<>;

        #cf. OAuth 2.0 4.1.2.1
        if ( $error_code eq 'access_denied' ) {
            return 'openid_access_denied';
        }
    }

    my $exception_to_code = {
        'Cpanel::Exception::Authz::MissingCode'                    => 'missing_openid_code',
        'Cpanel::Exception::Authz::MissingState'                   => 'missing_openid_state',
        'Cpanel::Exception::Authz::InvalidExternalValidationToken' => 'invalid_openid_external_validation_token',
        'Cpanel::Exception::SessionExpired'                        => 'expired_session',
        'Cpanel::Exception::Authz::CallbackFailure'                => 'openid_communication',
        'Cpanel::Exception::Authz::AccessTokenRetrievalError'      => 'openid_unable_to_get_access_token',
        'Cpanel::Exception::InvalidParameter'                      => 'openid_provider_misconfigured',
        'Cpanel::Exception::Authz::MissingIdToken'                 => 'openid_missing_id_token',
        'Cpanel::Exception::InvalidSession'                        => 'invalid_session',

        'Cpanel::Exception::HTTP' => 'oidc_received_error',
    };

    for my $exception_ns ( keys %$exception_to_code ) {
        if ( $exception->isa($exception_ns) ) {
            return $exception_to_code->{$exception_ns};
        }
    }

    return undef;
}

sub _get_or_create_session_if_expired_or_non_existent {
    my ($self)     = @_;
    my $server_obj = $self->get_server_obj();
    my $session    = $server_obj->get_current_session();

    if ( !length $session || $session eq 'closed' || !Cpanel::Session::Load::session_exists_and_is_current($session) ) {
        $server_obj->killsession( $session, 'openid_connect' );
        $session = $server_obj->newsession(
            'needs_auth' => 1,
            'origin'     => {
                'method' => __PACKAGE__ . '::handler',
                'path'   => 'openid_connect',
            },
        );
    }

    return $session;
}

sub _get_provider_obj {
    my ($self) = @_;
    return $self->{'_provider_obj'};
}

sub _get_provider_name {
    my ($self) = @_;
    return $self->{'_provider_name'};
}

sub _execute_remote_openid_call_with_exception_handler {
    my ( $self, $coderef ) = @_;

    my @ret;
    try {
        local $SIG{__DIE__};    # Make sure the try/catch handles the exception
        @ret = $coderef->();
    }
    catch {
        require Cpanel::Exception;

        my $msg_code = _get_msg_code_from_callback_exception($_);

        #There’s no need to log this failure if the error was access_denied;
        #that just means that the user (probably from misplaced paranoia)
        #denied this server access to their external auth resources.

        my $error_string;
        my $provider_name = $self->_get_provider_name();
        if ( ( $msg_code || q<> ) ne 'openid_access_denied' ) {
            $error_string = "openid connect: '$Cpanel::App::appname' provider '$provider_name' encountered an error: " . Cpanel::Exception::get_string($_);
            $self->warn_in_error_log($error_string);
        }

        $self->_send_server_to_login_page(
            oidc_error     => $error_string,
            preserve_token => 1,
            ( $error_string ? ( 'faillog'  => $error_string ) : () ),
            ( $msg_code     ? ( 'msg_code' => $msg_code )     : () ),
            oidc_failed => $provider_name,
        );
    };

    return @ret;

}

sub _filter_user_by_calling_context {
    my ($user) = @_;

    return 0 if $user eq 'root'            && !Cpanel::App::is_whm();
    return 0 if !Cpanel::App::is_webmail() && Cpanel::AcctUtils::Lookup::Webmail::is_strict_webmail_user($user);
    return 0 if Cpanel::App::is_whm()      && !Cpanel::Reseller::isreseller($user);
    return 1;
}

sub _get_user_info_trapped {
    my ( $self, $access_token ) = @_;

    my $user_info_payload;
    $self->_execute_remote_openid_call_with_exception_handler(
        sub { $user_info_payload = $self->_get_user_info($access_token) },
    );

    return $user_info_payload;
}

#Response documented at:
#https://openid.net/specs/openid-connect-core-1_0.html#UserInfoResponse
sub _get_user_info {
    my ( $self, $access_token ) = @_;

    my $provider_obj = $self->_get_provider_obj();

    my $user_info_payload = $provider_obj->get_user_info($access_token);

    for ( values %$user_info_payload ) {
        utf8::encode($_) if !ref && length;
    }

    return $user_info_payload;
}

sub _load_user_info_and_update_cpuser_contact_email_if_needed {
    my ( $self, $username, $access_token ) = @_;

    if ( Cpanel::Server::Handlers::OpenIdConnect::ContactCopy::contact_email_needs_update($username) ) {

        my $email;

        # If they went though user selection via _handle_openid_need_to_select_user
        # because the openid account is linked to multiple cPanel users then the
        # openid_connect_email should already be in the session
        my $server_obj                = $self->get_server_obj();
        my $session_from_cookie       = $server_obj->get_current_session();
        my $user_provided_session_ref = Cpanel::Session::Load::loadSession($session_from_cookie);
        if ( $user_provided_session_ref && $user_provided_session_ref->{'openid_connect_email'} ) {
            $email = $user_provided_session_ref->{'openid_connect_email'};
        }

        # If the openid account is only linked to a single cPanel user then the
        # openid_connect_email will not already be in the session
        if ( !$email ) {
            my $user_info_payload;
            try {
                $user_info_payload = $self->_get_user_info($access_token);
                $email             = $self->_extract_email_from_userinfo_payload($user_info_payload);
            }
            catch {
                warn "Failed to load OIDC UserInfo: $_";
            };
        }
        if ($email) {
            Cpanel::Server::Handlers::OpenIdConnect::ContactCopy::save_user_contact_email(
                $username,
                $email,
            );
        }

    }

    return;
}

sub _extract_email_from_userinfo_payload {
    my ( $self, $user_info_payload ) = @_;
    return $user_info_payload->{'email'};
}

1;
