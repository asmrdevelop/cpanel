package Cpanel::SSL::cPStore::90Day;

# cpanel - Cpanel/SSL/cPStore/90Day.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use experimental 'isa';

=encoding utf-8

=head1 NAME

Cpanel::SSL::cPStore::90Day - Logic for the cPStore’s 90-day cert APIs

=head1 SYNOPSIS

    my $parse_obj = Cpanel::SSL::cPStore::90Day::parse_error($err);

    if ($parse_obj->is_fatal()) { .. }
    if ($parse_obj->is_error()) { .. }

    my $category = $parse_obj->category();

=head1 DESCRIPTION

This module contains logic to interface with the cPStore’s 90-day
certificate APIs.

=head1 SEE ALSO

https://cpanel.wiki/display/SDI/Store+API+Functions+-+Request+a+Free+90-day+Certificate

https://cpanel.wiki/display/SDI/Store+API+Functions+-+Revoke+a+Free+90-day+Certificate

=cut

#----------------------------------------------------------------------

use Cpanel::SSL::cPStore::90Day::FetchError    ();
use Cpanel::SSL::cPStore::90Day::FetchResponse ();

# These errors indicate that we should stop polling for the certificate
# because the order or the order item was canceled.
use constant _CANCELED_ERRORS => (
    'X::OrderCanceled',
    'X::OrderItemCanceled',
);

# These errors indicate that we should stop polling for the certificate
# because something weird/bad happened.
use constant _FINAL_ERRORS => (
    'X::ItemNotFound',
    'X::Item::NotFound',

    # Note that paid certificate orders (i.e., cP Market) ignore this error.
    # That’s for mostly historical reasons; with the unpaid/free certificates
    # we can be 100% certain that this error means we should discard the
    # certificate order.
    'X::CertificateNotFound',
);

#----------------------------------------------------------------------

=head1 ERROR CATEGORY CONSTANTS

This module defines several constants to indicate error categories:

=over

=item * C<ERROR_CATEGORY_UNAVAILABLE> - cPStore is down but just
temporarily.

=item * C<ERROR_CATEGORY_NEEDS_APPROVAL> - The cert order requires
some manual intervention. The order is just taking longer than it
normally would.

=item * C<ERROR_CATEGORY_CANCELED> - The cert order was canceled.
We assume that the user is aware of the cancellation.

=item * C<ERROR_CATEGORY_UNRECOGNIZED> - cPStore doesn’t recognize
this cert order for some reason. That shouldn’t normally happen.

=item * C<ERROR_CATEGORY_GENERAL> - The cert fetch failed for an
unspecified reason. This is hopefully just something transient.

=item * C<ERROR_CATEGORY_UNKNOWN> - Some other kind of failure.
Give the error to the user; that’s all we’ve got at this point.

=back

=cut

use constant {
    map { $_ => tr<A-Z><a-z>r } (
        'ERROR_CATEGORY_UNAVAILABLE',
        'ERROR_CATEGORY_NEEDS_APPROVAL',
        'ERROR_CATEGORY_CANCELED',
        'ERROR_CATEGORY_UNRECOGNIZED',
        'ERROR_CATEGORY_GENERAL',
        'ERROR_CATEGORY_UNKNOWN',
    )
};

use constant {
    _BRANDING => 'cpanel',    # … or “comodo”

    _FOR_USER_URI   => 'ssl/certificate/free',
    _FOR_SYSTEM_URI => 'ssl/certificate/whm-license/90-day',
};

my $BASE_RELATIVE_URI = _FOR_USER_URI;

#----------------------------------------------------------------------

=head1 FUNCTIONS

#----------------------------------------------------------------------

=head2 $order = order_for_user( %OPTS )

Orders a single (cPanel-branded) certificate from cPStore’s endpoint
for user 90-day certificates.

This throws I<only> in the event of an error from cPStore.

Returns cPStore’s response as a hashref. Currently the
only important piece of information in that response is the C<order_item_id>;
a response that lacks that may be considered a failure.

Thus, a call to this function B<MUST> check both for a thrown exception
I<and> a return that lacks C<order_item_id>.

%OPTS are:

=over

=item * C<cpstore> - A L<Cpanel::cPStore::LicenseAuthn> instance.

=item * C<csr> - The CSR, in PEM format.

=item * C<domains> - An arrayref of the CSR’s domains.

(We could parse this out of the C<csr>, but every caller always has
this already, and parsing the CSR is rather inefficient.)

=item * C<dcv_method> - A hashref as to give to
L<Cpanel::SSL::Providers::Sectigo>’s C<get_dcv_string_for_request()>.

=back

=cut

sub order_for_user (%opts) {
    return _order( _FOR_USER_URI, %opts );
}

sub order_for_system (%opts) {
    return _order( _FOR_SYSTEM_URI, %opts );
}

sub _order ( $relative_url, %opts ) {
    state @_order_needed = ( 'cpstore', 'csr', 'domains', 'dcv_method' );

    my @missing = grep { !length $opts{$_} } @_order_needed;
    die "need @missing" if @missing;

    local ( $@, $! );
    require Cpanel::SSL::Providers::Sectigo;

    my $dcv_string = Cpanel::SSL::Providers::Sectigo::get_dcv_string_for_request(
        @opts{ 'domains', 'dcv_method' },
    );

    return $opts{'cpstore'}->post(
        $relative_url,
        item_params => {
            %opts{'csr'},
            branding    => _BRANDING,
            dcv_methods => $dcv_string,
        },
    );
}

=head2 $resp = fetch( $CPSTORE_OBJ, $ORDER_ITEM_ID )

Tries to fetch a certificate from cPStore based on the given $ORDER_ITEM_ID
and returns a L<Cpanel::SSL::cPStore::90Day::FetchResponse> that indicates
the response from that query.

If the cPStore indicated an error, a
L<Cpanel::SSL::cPStore::90Day::FetchError> instance is thrown instead.

=cut

sub fetch ( $cpstore, $oiid ) {
    local $@;
    if ( my $resp = $cpstore->get("$BASE_RELATIVE_URI/$oiid") ) {
        return parse_fetch_response($resp);
    }

    die parse_fetch_error($@);
}

#----------------------------------------------------------------------

=head2 $status_obj = parse_fetch_response( \%RESPONSE )

This parses the %RESPONSE from a certificate-fetch into a
L<Cpanel::SSL::cPStore::90Day::FetchResponse> instance.

=cut

sub parse_fetch_response ($resp_hr) {
    return Cpanel::SSL::cPStore::90Day::FetchResponse->new(%$resp_hr);
}

#----------------------------------------------------------------------

=head2 $error_obj = parse_fetch_error( $ERROR )

This parses the $ERROR from a certificate-fetch request into a
L<Cpanel::SSL::cPStore::90Day::FetchError> instance.

($ERROR is normally
a L<Cpanel::Exception::cPStoreError> instance but can be anything.)

=cut

sub parse_fetch_error ($err) {
    state %type_to_category = (
        'X::TemporarilyUnavailable' => ERROR_CATEGORY_UNAVAILABLE,
        'X::RequiresApproval'       => ERROR_CATEGORY_NEEDS_APPROVAL,
        'X::GeneralFailure'         => ERROR_CATEGORY_GENERAL,
        ( map { $_ => ERROR_CATEGORY_CANCELED } _CANCELED_ERRORS ),
        ( map { $_ => ERROR_CATEGORY_UNRECOGNIZED } _FINAL_ERRORS ),
    );

    state %category_is_error = (
        ERROR_CATEGORY_UNRECOGNIZED() => 1,
        ERROR_CATEGORY_GENERAL()      => 1,
        ERROR_CATEGORY_UNKNOWN()      => 1,
    );

    state %category_is_final = (
        ERROR_CATEGORY_CANCELED()     => 1,
        ERROR_CATEGORY_UNRECOGNIZED() => 1,
    );

    my $category;

    if ( $err isa Cpanel::Exception::cPStoreError ) {
        $category = $type_to_category{ $err->get('type') };
    }

    # NB: We let X::PermissionDenied be in this category.
    $category ||= ERROR_CATEGORY_UNKNOWN;

    my @extras;

    local $@;
    if ( eval { $err->can('get') } ) {
        @extras = map { $err->get($_) } qw( type message );
    }

    return Cpanel::SSL::cPStore::90Day::FetchError->new(
        category => $category,
        is_error => $category_is_error{$category} || 0,
        is_final => $category_is_final{$category} || 0,
        @extras,
    );
}

1;
