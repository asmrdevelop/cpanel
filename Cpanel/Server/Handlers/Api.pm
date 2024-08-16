package Cpanel::Server::Handlers::Api;

# cpanel - Cpanel/Server/Handlers/Api.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;
use feature qw/signatures/;

use Cpanel::Try               ();
use Cpanel::Exception         ();
use Cpanel::PwCache           ();
use Cpanel::Server::Constants ();
use Cpanel::XML               ();

=encoding utf-8

=head1 NAME

Cpanel::Server::Handlers::Api - Api handler for cpsrvd

=head1 SYNOPSIS

Calling a uapi call from cpanel. Remember the info for the api call is in the
C<$server_obj->get_document()> and the submitted request body.

    my $api_type = 'uapi'; # can also be 'json-uapi'

    $server_obj->get_handler('Api')->handler($api_type, {
        session_temp_user => $session_temp_user,
        session_temp_pass => $session_temp_pass,
        successful_external_auth_with_timestamp => $successful_external_auth_with_timestamp,
        webmail => 1,
    });

Calling an Api2 call from webmail. Similar to UAPI above the info for the api call
is in the C<$server_obj->get_document()> and the submitted request body.

    my $api_type = 'json-api';

    $server_obj->get_handler('Api')->handler($api_type, {
        session_temp_user => $session_temp_user,
        session_temp_pass => $session_temp_pass,
        successful_external_auth_with_timestamp => $successful_external_auth_with_timestamp,
        webmail => 1,
    });

=head1 DESCRIPTION

This module is handler that works in cpsrvd to make Api calls as requests
dictate. It subclasses L<Cpanel::Server::Handler>.

B<DEVELOPER NOTES:>

A UAPI call from the webmail context has not been tried yet.

Url format for APIs:

=over

=item UAPI

C</execute/{module}/{function}>

=item API2 - JSON

C</json-api/cpanel>

=item API2 - XML [DEPRECATED]

C</xml-api/cpanel>

=back

=cut

use parent 'Cpanel::Server::Handler';

=head1 METHODS

=head2 I<INSTANCE>->handler( $API_TYPE, $OPTIONS )

=head3 ARGUMENTS

=over

=item $API_TYPE - string

One of:

=over

=item uapi - UAPI (Defaults to JSON output)

=item json-api - API2

=item json-uapi - UAPI

=back

=item $OPTIONS - hashref

Where the hash contains the following properties:

=over

=item mime_types - dictionary<string, string>

A ref to the table of MIME types from cpsrvd.

=item session_temp_user - string

The sessions temporary user or undefined.

=item session_temp_pass - string

The sessions temporary password or undefined.

=item successful_external_auth_with_timestamp - boolean

True when an external auth provider was used to login.

=item webmail - boolean

True when called from the webmail application context. Missing otherwise.

=back

=back

=cut

sub handler ( $self, $api_type, $options = {} ) {
    my $server_obj = $self->get_server_obj();

    $server_obj->setup_cgi_variables();

    my $document = $server_obj->request()->get_document();
    substr( $document, 0, 2, '' ) while index( $document, './' ) == 0;

    # NOTE: Some API calls depend on this global being initialized.
    $Cpanel::homedir = Cpanel::PwCache::gethomedir($>);

    my $form_ref = Cpanel::Try::try(
        sub {
            $server_obj->timed_parseform( 120, 1 );
        },
        'Cpanel::Exception::TempFileCreateError' => sub {
            my $err = $@;

            if ( eval { $err->error_name() eq 'EDQUOT' } ) {
                die Cpanel::Exception::create('cpsrvd::PayloadTooLarge');
            }

            local $@ = $err;
            die;
        },
    );

    ## UAPI gets its output format from api.output parameter (or defaults to JSON)
    if ( $api_type eq 'uapi' ) {
        $api_type = 'json-uapi';
    }
    $options->{'json'} = ( $api_type eq 'json-api' || $api_type eq 'json-uapi' );

    ## UAPI gets $module and $function from $document (e.g. ./execute/Module/function?params...)
    if ( $api_type =~ m/-uapi$/ ) {
        $options->{'uapi'} = 1;
        my ( $module, $function ) = ( $document =~ m!^execute/([^/]+)/([^?]+)! );
        $form_ref->{'api.module'}   = $module;
        $form_ref->{'api.function'} = $function;
    }

    my $remote_pass_value = ( ( $Cpanel::App::appname ne 'webmaild' && $ENV{'CPRESELLER'} ) ? '__HIDDEN__' : $server_obj->auth()->get_pass() );
    local $ENV{'REMOTE_PASSWORD'} = $remote_pass_value if defined $remote_pass_value;
    local $ENV{'REMOTE_PASSWORD'} = ''                 if $options->{'session_temp_pass'};

    local $ENV{'CPANEL_EXTERNAL_AUTH'} = 1                               if $options->{'successful_external_auth_with_timestamp'};
    local $ENV{'SESSION_TEMP_USER'}    = $options->{'session_temp_user'} if $options->{'session_temp_user'};
    local $ENV{'SESSION_TEMP_PASS'}    = $options->{'session_temp_pass'} if $options->{'session_temp_pass'};

    ## UAPI note: cpanel_exec_fast makes the decision to go to legacy cpanel(.pl) binary or uapi(.pl)
    my ( $serialized_results_length, $serialized_results_ref, $internal_error, $internal_error_reason ) = Cpanel::XML::cpanel_exec_fast( $form_ref, $options );
    if ( $serialized_results_length && !$internal_error ) {
        my $output_headers = $server_obj->fetchheaders(
            $Cpanel::Server::Constants::FETCHHEADERS_STATIC_CONTENT,    #
            $Cpanel::Server::Constants::HTTP_STATUS_OK,                 #
            $Cpanel::Server::Constants::FETCHHEADERS_SKIP_LOGACCESS     #
          ) . $server_obj->nocache()                                    #
          . 'Content-type: ' . $options->{'mime_types'}{'json'} . "\r\n";
        return $server_obj->write_content_to_socket( \$output_headers, $serialized_results_ref );
    }
    else {
        my $http_status = ( $server_obj->upgrade_in_progress() ? $Cpanel::Server::Constants::HTTP_STATUS_SERVICE_UNAVAILABLE : $Cpanel::Server::Constants::HTTP_STATUS_INTERNAL_ERROR );
        my $api_version;
        if ( $api_type =~ m/-uapi$/ ) {
            $api_version = 3;
        }
        elsif ( $form_ref && $form_ref->{'cpanel_jsonapi_apiversion'} ) {
            $api_version = ( $form_ref->{'cpanel_jsonapi_apiversion'} eq '1' ? 1 : 2 );

            # We aren’t able to filter API 1 in Cpanel::Server::Auth::HTTP
            # because at that point we only know the request path, and
            # the distinction between API 1 and API 2 can be sent in the
            # request payload (i.e., the POST) as well as the URL query.
            # So we have to filter it here.
            if ( $api_version == 1 && $server_obj->auth()->get_auth_type() eq 'token' ) {

                die Cpanel::Exception::create_raw( 'cpsrvd::Forbidden', 'Token authentication allows access to UAPI or API 2 calls only.' );
            }
        }
        $server_obj->handle_subprocess_failure( $http_status, $api_type, $api_version, $internal_error_reason );
    }
    return 1;
}

1;
