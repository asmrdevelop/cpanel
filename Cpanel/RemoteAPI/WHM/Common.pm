package Cpanel::RemoteAPI::WHM::Common;

# cpanel - Cpanel/RemoteAPI/WHM/Common.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::WHM::Base

=head1 DESCRIPTION

This module implements common logic for WHM API client modules.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 create_general_error ($FUNCNAME, $HOSTNAME, $USERNAME, $ERRSTR, $RESPONSE)

Throws a L<Cpanel::Exception> that indicates a generic error (e.g.,
an HTTP failure).

=cut

sub create_general_error ( $fn, $hostname, $username, $error ) {
    return Cpanel::Exception::create( "API::WHM1", "The system failed to send the “[_1]” request to “[_2]” as “[_3]”: [_4]", [ $fn, $hostname, $username, $error ] );
}

=head2 create_api_error ($FUNCNAME, $HOSTNAME, $USERNAME, $ERRSTR, $RESPONSE)

Throws a L<Cpanel::Exception> that indicates an error response from the
API (e.g., invalid function parameters).

=cut

sub create_api_error ( $fn, $hostname, $username, $error, $resp ) {
    return Cpanel::Exception::create( "API::WHM1", "The “[_1]” request to “[_2]” as “[_3]” failed because of an error: [_4]", [ $fn, $hostname, $username, $error ], { response => $resp } );
}

1;
