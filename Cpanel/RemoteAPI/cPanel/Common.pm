package Cpanel::RemoteAPI::cPanel::Common;

# cpanel - Cpanel/RemoteAPI/cPanel/Common.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::cPanel::Common

=head1 SYNOPSIS

    Cpanel::RemoteAPI::cPanel::Common::create_general_error('Email', 'list_pops', 'the.hostname', 'bob', 'this is why', $resp_obj);

=head1 DESCRIPTION

This module implements common logic for remote API modules that call
cPanel APIs.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 create_general_error ($NAMESPACE, $FUNCNAME, $HOSTNAME, $USERNAME, $ERRSTR)

Throws a L<Cpanel::Exception> that indicates a generic error (e.g.,
an HTTP failure).

$RESPONSE is the object received back from the remote API module.
Its interface may vary according to which module that is.

=cut

sub create_general_error ( $ns, $fn, $hostname, $username, $error ) {
    return Cpanel::Exception::create( "API::UAPI", "The system failed to send the “[_1]” request to “[_2]” as “[_3]”: [_4]", [ "${ns}::$fn", $hostname, $username, $error ] );
}

=head2 create_api_error ($NAMESPACE, $FUNCNAME, $HOSTNAME, $USERNAME, $ERRSTR, $RESPONSE)

Throws a L<Cpanel::Exception> that indicates an error response from the
API (e.g., invalid function parameters).

$RESPONSE is the object received back from the remote API module.
Its interface may vary according to which module that is.

=cut

sub create_api_error ( $ns, $fn, $hostname, $username, $error, $resp ) {    ## no critic qw(ManyArgs) - for consistency w/ the function above
    return Cpanel::Exception::create( "API::UAPI", "The “[_1]” request to “[_2]” as “[_3]” failed because of an error: [_4]", [ "${ns}::$fn", $hostname, $username, $error ], { response => $resp } );
}

1;
