package Cpanel::Async::RemoteAPI::WHM;

# cpanel - Cpanel/Async/RemoteAPI/WHM.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Async::RemoteAPI::WHM

=head1 SYNOPSIS

    use Cpanel::Async::RemoteAPI::WHM ();

    my $api = Cpanel::Async::RemoteAPI::WHM->new_from_password(
        "10.1.35.45",
        "root",
        "my$ekre+",
    );

    my $listips_p = $api->request_whmapi1("listips")->then(
        sub ($response) {
            print Dumper $response->get_data();
        },
    );

    my $list_pops_p = $api->request_cpanel_uapi(
        'hank', Email => 'list_pops'
    )->then(
        sub ($response) { .. }
    );

    Cpanel::PromiseUtils::wait_anyevent($listips_p, $list_pops_p);

=head1 DESCRIPTION

A L<Cpanel::Async::RemoteAPI> subclass for running remote APIs via WHM.

=cut

# perl -Mstrict -w -MCpanel::Async::RemoteAPI::WHM -MCpanel::PromiseUtils -MData::Dumper -e'my $api = Cpanel::Async::RemoteAPI::WHM->new_from_password("10.1.35.45", "root", "SECRET")->disable_tls_verify(); my $pend = $api->request_whmapi1("listips"); print Dumper( Cpanel::PromiseUtils::wait_anyevent( $pend ) )'

#----------------------------------------------------------------------

use parent 'Cpanel::Async::RemoteAPI';

use Cpanel::RemoteAPI::cPanel::Common ();
use Cpanel::RemoteAPI::WHM::Common    ();

sub _CPANEL_APICLIENT_SERVICE ($) {
    return 'whm';
}

#----------------------------------------------------------------------

=head1 METHODS

=head2 promise($result) = I<OBJ>->request_whmapi1( $FUNCNAME [, \%PARAMS] )

Calls a WHM API v1 function (named by $FUNCNAME, with parameters %PARAMS)
and returns a promise that
resolves to a L<cPanel::APIClient::Response::WHM1> instance.

The returned promise is a L<Cpanel::Promise::Interruptible> instance;
C<interrupt()> on that promise will cancel the request.

B<IMPORTANT:> This method, B<UNLIKE> its counterpart in
L<Cpanel::RemoteAPI::WHM>, will I<reject> if the API result indicates a
failure.

See L<https://go.cpanel.net/whmapi1>
for details about the different API functions and the arguments they can
receive.

=cut

sub request_whmapi1 ( $self, $funcname, $args_hr = undef ) {
    my $hostname = $self->get_hostname();
    my $username = $self->get_username();

    return $self->_request_whmapi1_no_die( $funcname, $args_hr )->then(
        sub ($response) {
            if ( my $error = $response->get_error() ) {
                die Cpanel::RemoteAPI::WHM::Common::create_api_error(
                    $funcname, $hostname, $username, $error, $response,
                );
            }

            return $response;
        },
        $self->_general_whm_error_handler($funcname),
    );
}

=head2 promise($result) = I<OBJ>->request_cpanel_uapi( $USERNAME, $NAMESPACE, $FUNCNAME, [, \%PARAMS] )

Like C<request_whmapi1> but runs a cPanel UAPI call as $USERNAME.

See L<https://go.cpanel.net/uapidocs>
for more details about UAPI.

=cut

sub request_cpanel_uapi ( $self, $username, $ns, $funcname, $args_hr = undef ) {    ## no critic qw(ManyArgs)
    my $hostname = $self->get_hostname();

    return $self->_request_cpanel_uapi_no_die( $username, $ns, $funcname, $args_hr )->then(
        sub ($response) {
            if ( !$response->succeeded() ) {
                die Cpanel::RemoteAPI::cPanel::Common::create_api_error(
                    $ns, $funcname, $hostname, $username,
                    $response->get_errors_as_string(),
                    $response,
                );
            }

            return $response;
        },
        sub ($error) {
            die Cpanel::RemoteAPI::cPanel::Common::create_general_error(
                $ns, $funcname, $hostname, $username, $error,
            );
        },
    );
}

# Mocked in tests:
sub _request_cpanel_uapi_no_die ( $self, $username, $ns, $funcname, $args_hr ) {    ## no critic qw(ManyArgs)
    return $self->_request( 'call_cpanel_uapi', $username, $ns, $funcname, $args_hr );
}

# Mocked in tests:
sub _request_whmapi1_no_die ( $self, $funcname, $args_hr ) {
    return $self->_request( 'call_api1', $funcname, $args_hr );
}

sub _general_whm_error_handler ( $self, $funcname ) {
    my $hostname = $self->get_hostname();
    my $username = $self->get_username();

    return sub ($error) {
        die Cpanel::RemoteAPI::WHM::Common::create_general_error(
            $funcname, $hostname, $username, $error,
        );
    };
}

1;
