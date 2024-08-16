package Whostmgr::API::1::Utils::TLS;

# cpanel - Whostmgr/API/1/Utils/TLS.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Whostmgr::API::1::Utils::TLS

=head1 SYNOPSIS

    my $err_obj = Whostmgr::API::1::Utils::TLS::create_remoteapi_typed_error_if_tls(
        $errstring,
        $args->{'host'},
        $Cpanel::Services::Ports::SERVICE{'whostmgrs'},
    );

=head1 DESCRIPTION

This module contains reusable pieces of TLS-related functionality for
WHM API v1.

=cut

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj_or_undef = create_remoteapi_typed_error_if_tls( $ERRSTRING, $HOST, $PORT )

Examines $ERRSTRING and, if it looks like a TLS error from
L<Cpanel::RemoteAPI>, returns a hashref with more details about
the TLS failure.

If $ERRSTRING doesn’t look like such an error, returns undef.

This happens by making a 2nd connection. There’s no guarantee that that
2nd connection’s failure will be what caused the error that created
$ERRSTRING. In fact, there’s no guarantee that the 2nd connection will
fail at all! In light of this, take note of the following edge cases:

=over

=item * The 2nd connection might fail for some weird other reason, e.g.,
TCP failure. When this happens, undef is returned, and a warning about the
other failure is thrown.

=item * The 2nd connection might fail for an altogether different reason.
There’s no good way to detect this, unfortunately.

=back

The returned hashref will have the same structure as the return of
L<Cpanel::APICommon::Error>’s C<convert_to_payload()> function. The
C<type> will be C<TLSVerification>, and the C<detail> will be a hash
reference of:

=over

=item * C<chain> - An array reference of the server certificates, all
in PEM format.

=item * C<handshake_verify> - The OpenSSL code that indicates the reason
(if any) for OpenSSL’s verification failure.

=item * C<handshake_verify_text> - A text code for C<handshake_verify>,
taken from L<Cpanel::OpenSSL::Verify>.

=item * C<matches_host> - A boolean (0 or 1) that indicates whether the
certificate matches the given $HOST. (This is a convenience merely; this
value can be derived by comparing the top member of C<chain> with $HOST.)

=back

=cut

sub create_remoteapi_typed_error_if_tls ( $errstring, $host, $port ) {
    my $err_hr = _err_is_remoteapi_tls_err($errstring) || undef;
    $err_hr &&= create_typed_error_for_tls_verification( $host, $port );

    return $err_hr;
}

#----------------------------------------------------------------------

=head2 $obj_or_undef = create_typed_error_for_tls_verification( $HOST, $PORT )

Like C<create_remoteapi_typed_error_if_tls()> but doesn’t pre-verify
an error string. This can still return undef and warn, so be sure you
check the return.

=cut

sub create_typed_error_for_tls_verification ( $host, $port ) {

    require Cpanel::PromiseUtils;
    require Cpanel::SSL::RemoteFetcher;
    require Cpanel::APICommon::Error;
    require Cpanel::OpenSSL::Verify;
    require Cpanel::SSL::Objects::Certificate;

    my $fetcher = Cpanel::SSL::RemoteFetcher->new();

    my $result = Cpanel::PromiseUtils::wait_anyevent(
        $fetcher->fetch( $host, $port ),
    );

    my $err_obj;

    if ( my $err = $result->error() ) {
        warn "Failed to recheck TLS: $err";
    }
    else {
        my %data = %{ $result->get() };

        my $code = $data{'handshake_verify'};

        $data{'handshake_verify_text'} = Cpanel::OpenSSL::Verify::error_code_to_name($code);

        my $leaf_pem = $data{'chain'}[0];

        $data{'matches_host'} = $leaf_pem && do {
            my $cert = Cpanel::SSL::Objects::Certificate->new( cert => $leaf_pem );

            $cert->valid_for_domain($host);
        };

        $err_obj = Cpanel::APICommon::Error::convert_to_payload( 'TLSVerification', %data );
    }

    return $err_obj;
}

sub _err_is_remoteapi_tls_err ($err) {

    # We used to check for 599 here, but cPanel::PublicAPI only puts
    # that in its error message for password-authenticated connections,
    # so API tokens don’t see it. Instead let’s look for how Net::SSLeay
    # indicates that failure.
    my @ssl_funcs = (
        '',                                  # RHEL 9 - OpenSSL 3.x
        'tls_process_server_certificate',    # CentOS 8
        'ssl3_get_server_certificate',       # CentOS 6 & 7
    );

    my $ssl_funcs_str = join '|', @ssl_funcs;

    return $err =~ m[SSL routines:(?:$ssl_funcs_str):certificate verify failed]i;    #case insensitive because at least one OpenSSL version alternates case
}

1;
