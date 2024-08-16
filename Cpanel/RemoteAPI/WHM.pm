package Cpanel::RemoteAPI::WHM;

# cpanel - Cpanel/RemoteAPI/WHM.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::RemoteAPI );

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::WHM

=head1 SYNOPSIS

    my $obj = Cpanel::RemoteAPI::WHM->new_from_password(
        'host.name',
        'bob',
        'p4$$w0rd',
    );

    my $whm_result = $obj->request_whmapi1('createacct', \%params);

    my $uapi_result = $obj->request_cpanel_uapi('joe', 'Email', 'listautoresponders', \%params);

=head1 DESCRIPTION

This class subclasses L<Cpanel::RemoteAPI> for access to a remote
WHM service.

This is what you use to execute B<either> WHM or cPanel calls in
a remote WHM.

=cut

#----------------------------------------------------------------------

use Cpanel::RemoteAPI::cPanel::Common ();
use Cpanel::RemoteAPI::WHM::Common    ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 $result = I<OBJ>->request_whmapi1( $FUNCNAME, \%PARAMS )

Calls a WHM API v1 function and returns a
L<Whostmgr::API::1::Utils::Result> instance.

%PARAMS is filtered through C<Cpanel::APICommon::args::expand_array_args()>,
so you can submit an array reference as a value, and it’ll expand to
values that L<Whostmgr::API::1::Utils> can reassemble. (The passed-in
hash reference is not modified.)

Owing to implementation details, exceptions are thrown only for certain
(poorly-defined) failures. A not-necessarily-complete list of these follows:

=over

=item * Connection errors trigger an exception that contains the string
C<599 Internal Exception ($DETAIL)>, where $DETAIL is a human-readable
description of the failure. In particular, a TLS handshake $DETAIL
begins with C<SSL connection failed>.

=back

Specifically, note that failures from the API do B<NOT> trigger an exception;
you have to inspect the returned object.

=cut

sub request_whmapi1 {
    my ( $self, $fn, $args_hr ) = @_;

    $args_hr = $self->_expand_array_args($args_hr);

    require Whostmgr::API::1::Utils::Result;

    # $hr will be undef if the cPanel::PublicAPI detects a specific
    # failure, e.g., a call to a nonexistent API call. This can happen
    # if a call is made to a WHM API that the remote doesn’t know about
    # (e.g., if it’s too old to service the requested API call).
    #
    # NB: In this case, cPanel::PublicAPI prints the real error to STDERR.
    #
    my $hr = $self->_publicapi_obj()->whm_api( $fn, $args_hr );

    die "No response to “$fn” request! (Check STDERR.)" if !$hr;

    return Whostmgr::API::1::Utils::Result->new($hr);
}

=head2 $result = I<OBJ>->request_whmapi1_or_die( $FUNCNAME, \%PARAMS )

This function is identical to C<request_whmapi1> except that it will throw a
L<Cpanel::Exception::API::WHM1> exception if the API request fails to execute
or if the result indicates the API request had errors.

=cut

sub request_whmapi1_or_die {

    my ( $self, $fn, $args_hr ) = @_;

    local $@;
    my $resp = eval { $self->request_whmapi1( $fn, $args_hr ); };

    if ( !$resp ) {
        my $err = $@;

        die Cpanel::RemoteAPI::WHM::Common::create_general_error(
            $fn, $self->get_hostname(), $self->get_username(), $err,
        );
    }
    elsif ( my $error = $resp->get_error() ) {
        die Cpanel::RemoteAPI::WHM::Common::create_api_error(
            $fn, $self->get_hostname(), $self->get_username(), $error, $resp,
        );
    }

    return $resp;
}

#----------------------------------------------------------------------

=head2 $result = I<OBJ>->request_cpanel_uapi( $CPUSERNAME, $MODULENAME, $FUNCNAME, \%PARAMS )

Calls a UAPI function for the remote cPanel user with the given
username and returns a L<Cpanel::Result> instance.

Owing to implementation details, exceptions are thrown only for certain
(poorly-defined) failures

Note that failures from the API are B<NOT> reported via exception;
you have to inspect the returned object.

=cut

sub request_cpanel_uapi {
    my ( $self, $cpusername, $module, $fn, $args_hr ) = @_;

    local $args_hr->{'cpanel_jsonapi_apiversion'} = 3;
    local $args_hr->{'cpanel_jsonapi_module'}     = $module;
    local $args_hr->{'cpanel_jsonapi_func'}       = $fn;
    local $args_hr->{'cpanel_jsonapi_user'}       = $cpusername;

    local ( $@, $! );
    require Cpanel::RemoteAPI::Backend::cPanel;

    return Cpanel::RemoteAPI::Backend::cPanel::request_uapi(
        $self->_publicapi_obj(),
        sub {

            # If an unknown username is sent to the remote in a WHM request,
            # then as of v88 cpsrvd responds with a strange payload like:
            #
            # {
            #   "data": {
            #       "reason": "User parameter is invalid or was not supplied",
            #       "result": "0"
            #   },
            #   "type": "text",
            #   "error": "User parameter is invalid or was not supplied"
            # }
            #
            # So let’s try to recognize this and deal with it.

            if ( !$_[0]->{'result'} ) {
                if ( my $error = $_[0]->{'error'} ) {
                    die "Remote UAPI request failed: $error";
                }
            }

            $_[0] = $_[0]->{'result'};
        },
        'whostmgr',
        "/json-api/cpanel",
        'POST',
        $args_hr,
    );
}

=head2 $result = I<OBJ>->request_cpanel_uapi_or_die( $CPUSERNAME, $MODULENAME, $FUNCNAME, \%PARAMS )

This function is identical to C<request_cpanel_uapi> except that it will throw a
L<Cpanel::Exception::API::UAPI> exception if the API request fails to execute
or if the result indicates the API request had errors.

=cut

sub request_cpanel_uapi_or_die {

    my ( $self, $cpusername, $module, $fn, $args_hr ) = @_;

    local $@;
    my $resp = eval { $self->request_cpanel_uapi( $cpusername, $module, $fn, $args_hr ); };

    if ( !$resp ) {
        my $err = $@;

        die Cpanel::RemoteAPI::cPanel::Common::create_general_error(
            $module,                  $fn,
            $self->{_api_args}{host}, $cpusername,
            $err,
        );
    }
    elsif ( my $error = $resp->errors_as_string() ) {
        die Cpanel::RemoteAPI::cPanel::Common::create_api_error(
            $module,                  $fn,
            $self->{_api_args}{host}, $cpusername,
            $error,                   $resp
        );
    }

    return $resp;
}

1;
