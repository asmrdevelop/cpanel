package Cpanel::RemoteAPI::Backend::cPanel;

# cpanel - Cpanel/RemoteAPI/Backend/cPanel.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::RemoteAPI::Backend::cPanel

=head1 SYNOPSIS

    Cpanel::RemoteAPI::Backend::cPanel::request_uapi(
        $publicapi_obj,
        \@args,
    );

=head1 DESCRIPTION

This module exists to deduplicate logic between cPanel- and WHM-service
subclasses of L<Cpanel::RemoteAPI>. It isn’t meant to be called outside
that namespace.

=cut

#----------------------------------------------------------------------

use Cpanel::APICommon::Args ();
use Cpanel::JSON            ();

#----------------------------------------------------------------------

=head2 $result = request_uapi( $PUBLICAPI_OBJ, $XFORM_CR, @ARGS )

This is the function that implements UAPI functionality for
L<Cpanel::RemoteAPI> subclasses. It returns an instance of
L<Cpanel::Result>.

$PUBLICAPI_OBJ is a L<cPanel::PublicAPI> instance.

@ARGS are the arguments given to $PUBLICAPI_OBJ’s C<api_request()> method.
Note that $ARGS[3] will be expanded per
L<Cpanel::APICommon::Args>’s C<expand_array_refs()> beforehand.
(The passed-in data structure will be unchanged.)

$XFORM_CR is applied to the JSON-decoded result of that
C<api_request()> call before being turned into the final
L<Cpanel::Result> instance.

See L<Cpanel::RemoteAPI::cPanel> for more information.

=cut

sub request_uapi ( $publicapi_obj, $xform_cr, @args ) {

    # This turns ( foo => [ 'bar', 'baz' ] ) into
    # ( foo => 'bar', foo-0 => 'baz' ).
    $args[3] = Cpanel::APICommon::Args::expand_array_refs( $args[3] );

    local ( $@, $! );
    require Cpanel::Result;

    my ( $status, $msg, $resp ) = $publicapi_obj->api_request(@args);

    die "Remote UAPI request error: $msg" if !$status;

    my $response_hr = Cpanel::JSON::Load($$resp);

    $xform_cr->($response_hr);

    return Cpanel::Result->new_from_hashref($response_hr);
}

1;
