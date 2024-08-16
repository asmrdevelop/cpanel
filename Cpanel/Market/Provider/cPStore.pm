package Cpanel::Market::Provider::cPStore;

# cpanel - Cpanel/Market/Provider/cPStore.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE: This module is called “cPStore” rather than “Sectigo” because the
# module interacts with the cPStore, not Sectigo directly. The parts of it
# that are dependent on Sectigo are marked clearly.
#----------------------------------------------------------------------

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Market::Provider::cPStore - cPanel’s cPanel Market provider

=head1 DESCRIPTION

This module provides access in cPanel & WHM to items that are sold via the
cPanel Store.

Strictly speaking, the functions here don’t need to be documented because
they’re documented in L<the cPanel Market provider module documentation|https://go.cpanel.net/custommarketproviderwizard>;
however, for ease of development within cPanel some documentation is given
here.

=cut

use Try::Tiny;

use Cpanel::Imports;

use Cpanel::Autodie                                  ();
use Cpanel::cPStore                                  ();
use Cpanel::cPStore::LicenseAuthn                    ();    # used by $_CPSTORE_LICENSEAUTH_MODULE
use Cpanel::CommandQueue                             ();
use Cpanel::Context                                  ();
use Cpanel::Exception                                ();
use Cpanel::Exception::External                      ();
use Cpanel::FileUtils::Write                         ();
use Cpanel::HTTP::QueryString                        ();
use Cpanel::OrDie                                    ();
use Cpanel::Mkdir                                    ();
use Cpanel::Market::Provider::cPStore::Constants     ();
use Cpanel::Market::Provider::cPStore::ProductsCache ();
use Cpanel::Validate::EmailRFC                       ();
use Cpanel::Security::Authz                          ();
use Cpanel::SSL::Providers::Sectigo                  ();
use Cpanel::SSL::Utils                               ();
use Cpanel::WildcardDomain::Tiny                     ();

=head1 FUNCTIONS

=cut

use constant {
    SKIP_MISSING_DOCROOTS => 1,

    DIE_MISSING_DOCROOTS => 0,

    _DNS_DCV_RECORD_TYPE => 'CNAME',
};

my %VALID_VALIDITY_COUNTS = (
    day => [90],

    #year => [ 1, 2, 3 ],

    year => [1],
);

#requires a redirect URL as argument
*get_login_url = \&Cpanel::cPStore::LOGIN_URI;

#requires an order ID as argument
*get_checkout_url     = \&Cpanel::cPStore::CHECKOUT_URI;
*get_checkout_url_whm = \&Cpanel::cPStore::CHECKOUT_URI_WHM;

my @ACCEPTED_SUBJECT_NAME_TYPES = qw(
  dNSName
);

sub _DISPLAY_NAME { return 'cPanel Store' }

*URI_DCV_RELATIVE_PATH          = *Cpanel::Market::Provider::cPStore::Constants::URI_DCV_RELATIVE_PATH;
*REQUEST_URI_DCV_PATH           = *Cpanel::Market::Provider::cPStore::Constants::REQUEST_URI_DCV_PATH;
*URI_DCV_ALLOWED_CHARACTERS     = *Cpanel::Market::Provider::cPStore::Constants::URI_DCV_ALLOWED_CHARACTERS;
*URI_DCV_RANDOM_CHARACTER_COUNT = *Cpanel::Market::Provider::cPStore::Constants::URI_DCV_RANDOM_CHARACTER_COUNT;
*EXTENSION                      = *Cpanel::Market::Provider::cPStore::Constants::EXTENSION;
*DCV_USER_AGENT                 = *Cpanel::Market::Provider::cPStore::Constants::DCV_USER_AGENT;
*HTTP_DCV_MAX_REDIRECTS         = *Cpanel::Market::Provider::cPStore::Constants::HTTP_DCV_MAX_REDIRECTS;

# If the provider supports profit sharing/commission
sub provider_supports_commission { return 1; }

#The number to use to validate prices.
#Prices must fit the following equation:
#
#   $price % ($even_commission_divisor / 100) == 0;
#
#NOTE: This value affects a price per DOMAIN PAIR, defined as the given
#domain IN ADDITION TO that domain’s “www.” subdomain. (e.g., foo.tld
#and www.foo.tld)
sub even_commission_divisor { return 12; }

#Accepts:
#   order_id
#   order_item_id
sub get_support_uri_for_order_item {
    my (%opts) = @_;

    return 'mailto:cs@cpanel.net?' . Cpanel::HTTP::QueryString::make_query_string(
        subject => "Help with order item $opts{'order_item_id'} (order $opts{'order_id'})",
    );
}

=head2 get_support_uri_for_order( %OPTS )

Provides a URI that can be used in messages directing users to contact CS
for support with an order.

=head3 Arguments

%OPTS - A hash of options.

=over

=item

order_id (required) - The order ID for the problem order.

=back

=head3 Returns

A string containing the support URI.

=cut

sub get_support_uri_for_order {
    my (%opts) = @_;

    return 'mailto:cs@cpanel.net?' . Cpanel::HTTP::QueryString::make_query_string(
        subject => "Help with order $opts{'order_id'}",
    );
}

#login token and redirect URL as argument
#Returns a hashref with at least “access_token” in the response.
sub validate_login_token {
    my (@args) = @_;

    my $ret_hr = Cpanel::cPStore::validate_login_token(@args);
    $ret_hr->{'access_token'} = delete $ret_hr->{'token'};

    return $ret_hr;
}

sub get_products_list {
    Cpanel::Context::must_be_list();

    my @list = _get_products_list_for_validation();

    #No sense in giving this to API clients.
    for my $item (@list) {
        next if !$item->{'x_identity_verification'};
        delete $_->{'_to_csr'} for @{ $item->{'x_identity_verification'} };
    }

    return @list;
}

#overridden in tests
sub _get_products_list_for_validation {
    return @{ Cpanel::Market::Provider::cPStore::ProductsCache->load() };
}

sub _validate_validity_period {
    my (%item_parts) = @_;

    if ( !length $item_parts{'validity_period'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'validity_period' ] );
    }

    if ( 'ARRAY' ne ref( $item_parts{'validity_period'} ) ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” must be an array, not “[_2]”.', [ 'validity_period', $item_parts{'validity_period'} ] );
    }

    my ( $validity_count, $validity_unit ) = @{ $item_parts{'validity_period'} };

    $_ //= q<> for ( $validity_count, $validity_unit );

    my $valid_counts = $VALID_VALIDITY_COUNTS{$validity_unit};
    if ( !$valid_counts ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'A validity period unit describes the unit of time with which the system measures a certificate’s validation period. “[_1]” is not a valid validity period unit. The validity period unit must be one of: [join,~, ,_2]', [ $validity_unit, [ sort keys %VALID_VALIDITY_COUNTS ] ] );
    }

    return;
}

sub _get_product_list_entry_for_product_id {
    my ($product_id) = @_;

    my ($item_hr) = grep { $_->{'product_id'} eq $product_id } _get_products_list_for_validation();

    if ( !$item_hr ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” does not have a product with product [asis,ID] “[_2]”.', [ ( __PACKAGE__ =~ s<.*::><>r ), $product_id ] );
    }

    return $item_hr;
}

sub validate_request_for_one_item {
    my (%item_parts) = @_;

    if ( !$item_parts{'product_id'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'product_id' ] );
    }

    my $product_id = $item_parts{'product_id'};
    my $item_hr    = _get_product_list_entry_for_product_id($product_id);

    #TODO: Most of this logic is not specific to cPStore and so should
    #really be in Cpanel/Market/SSL.pm
    if ( $item_hr->{'product_group'} eq 'ssl_certificate' ) {
        _validate_validity_period(%item_parts);

        if ( !$item_parts{'subject_names'} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ name => 'subject_names' ] );
        }

        if ( 'ARRAY' ne ref $item_parts{'subject_names'} ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'Each [asis,SSL] certificate’s “[_1]” must be an array, not “[_2]”.', [ 'subject_names', ref $item_parts{'subject_names'} ] );
        }

        if ( !@{ $item_parts{'subject_names'} } ) {
            die Cpanel::Exception::create( 'Empty', [ name => 'subject_names' ] );
        }

        #dcv_method is evaluated outside this module.
        for my $sn ( @{ $item_parts{'subject_names'} } ) {

            #All of cPStore’s products expect subject_names items to be
            #hashes now, not the old-style 2-member array references.
            my $type = $sn->{'type'};

            if ( !grep { $_ eq $type } @ACCEPTED_SUBJECT_NAME_TYPES ) {
                die Cpanel::Exception::create( 'InvalidParameter', 'This service only accepts the [list_and,_1] subject name [numerate,_2,type,types], not “[_3]”.', [ \@ACCEPTED_SUBJECT_NAME_TYPES, scalar(@ACCEPTED_SUBJECT_NAME_TYPES), $type ] );
            }
        }

        #Identity verification is evaluated prior to this module.
    }

    return;
}

#Accepts:
#   access_token (string)
sub get_logged_in_users_email {
    my (%opts) = @_;

    if ( !length $opts{'access_token'} ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'access_token' ] );
    }

    return Cpanel::cPStore->new( api_token => $opts{'access_token'} )->get('user')->{'email'};
}

#Receives a product ID and a list of key/value pairs.
#
#Returns a list of 2-member arrayrefs, i.e., such as goes into
#Cpanel::SSL::Create::csr().
#
#The values that come in here have already been validated.
#
sub convert_ssl_identity_verification_to_csr_subject {
    my ( $product_id, %id_verif ) = @_;

    Cpanel::Context::must_be_list();

    my @iden_ver = _get_iden_ver_for_product_id($product_id);

    my @allowed_parts = map { $_->{'_to_csr'} ? $_->{'name'} : () } @iden_ver;

    return _convert_identity_verification(
        \@allowed_parts,
        \%id_verif,
    );
}

#Same pattern as convert_ssl_identity_verification_to_csr_subject(),
#BUT this should return a plain list of key/value pairs.
#
sub convert_ssl_identity_verification_to_order_item_parameters {
    my ( $product_id, %id_verif ) = @_;

    Cpanel::Context::must_be_list();

    my @iden_ver = _get_iden_ver_for_product_id($product_id);

    my @allowed_parts = map { !$_->{'_to_csr'} ? $_->{'name'} : () } @iden_ver;

    return map { @$_ } _convert_identity_verification(
        \@allowed_parts,
        \%id_verif,
    );
}

# NB: This assumes that @$subject_names_ar is sorted properly.
#
sub convert_subject_names_to_dcv_order_item_parameters {
    my ( $product_id, $subject_names_ar ) = @_;

    Cpanel::Context::must_be_list();

    my @parts;
    for my $sn_hr (@$subject_names_ar) {
        my $dcv_method = $sn_hr->{'dcv_method'};

        my $comodo_method = Cpanel::SSL::Providers::Sectigo::DCV_METHOD_TO_SECTIGO()->{$dcv_method} or do {
            die "Unrecognized “dcv_method”: “$dcv_method” (@{$sn_hr}{'type','name'})";
        };

        push @parts, $comodo_method;
    }

    return ( dcv_methods => join ',', @parts );
}

sub _get_iden_ver_for_product_id {
    my ($product_id) = @_;

    my $product_entry = _get_product_list_entry_for_product_id($product_id);

    my $iden_ver_ar = $product_entry->{'x_identity_verification'};
    return $iden_ver_ar ? @$iden_ver_ar : ();
}

sub _convert_identity_verification {
    my ( $reference_ar, $id_verif_hr ) = @_;

    my %possible_parts = map { $_ => 1 } @$reference_ar;

    my @parts;

    for my $name ( keys %$id_verif_hr ) {
        my $value = $id_verif_hr->{$name};

        #skip this item since $name is not in $reference_ar
        next if !$possible_parts{$name};

        push @parts, [ $name => $id_verif_hr->{$name} ];
    }

    return @parts;
}

#Accepts:
#   access_token (string)
#   url_after_checkout (string, optional)
#   items: [
#       {
#           product_id => '...',
#           ...everything else is dependent on the actual item.
#       },
#       ...
#   ]
#
#Returns the checkout URL and an array ref of order item IDs,
#ordered as per the incoming “items” array reference.
#
sub create_shopping_cart {
    my (%opts) = @_;

    Cpanel::Context::must_be_list();

    for my $req (qw( access_token  items )) {
        if ( !$opts{$req} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ name => $req ] );
        }
    }

    if ( !@{ $opts{'items'} } ) {
        die Cpanel::Exception::create( 'Empty', [ name => 'items' ] );
    }

    my $cpstore = Cpanel::cPStore->new( api_token => $opts{'access_token'} );

    #The response to the POST that creates the order.
    my $api_order;

    #The last-received POST response.
    my $post;

    my $item_number;
    my $last_item;
    try {
        for my $item ( @{ $opts{'items'} } ) {
            $last_item = $item;
            $item_number++;

            my $endpoint = 'order';
            $endpoint .= "/$api_order->{'order_id'}" if $api_order;

            my %item_copy  = %$item;
            my $product_id = delete $item_copy{'product_id'} or do {
                die Cpanel::Exception::create( 'InvalidParameter', 'Every order item must have the parameter “[_1]”.', ['product_id'] );
            };

            $post = $cpstore->post(
                $endpoint,
                item_id     => $product_id,
                item_params => \%item_copy,
            );

            if ( !$api_order ) {
                $api_order = $post;

                #As soon as we have an order, attach the callback URL
                #to that order.
                if ( $opts{'url_after_checkout'} ) {
                    set_url_after_checkout(
                        'order_id'           => $api_order->{'order_id'},
                        'access_token'       => $opts{'access_token'},
                        'url_after_checkout' => $opts{'url_after_checkout'}
                    );
                }
            }
        }
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);
        _handle_authentication_failure($_);
        if ( $_->get('type') eq 'X::Validation::PricingError' ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The vendor has reported the correct price for item #[numf,_1] as $[_2] ([_3]).', [ $item_number, _format_dollars( $_->get('data')->{'item_price'} ), 'USD' ] );
        }
        if ( $_->get('type') eq 'X::Item::Validation::IPs' ) {
            die Cpanel::Exception::create( 'InvalidParameter', '[_1]', [ $_->get('data')->{'ips'}->[ $item_number - 1 ]->{'reason'} ] );
        }

        if ( $_->get('type') eq 'X::Item::Validation' && $last_item->{product_id} == $Cpanel::Market::Provider::cPStore::Constants::ITEM_IDS->{standard_trial_license} ) {
            die Cpanel::Exception::create( 'InvalidParameter', 'The IP address “[_1]” is not eligible for a free trial.', [ $last_item->{ip_address} ] );
        }

        local $@ = $_;
        die;
    };

    #The full list gets returned each time; however, as of 18 Feb 2016,
    #the order is not defined. A later item, though, will always
    #have a higher OIID, so we can safely sort here.
    my @order_items = sort { $a->{order_item_id} <=> $b->{order_item_id} } @{ $post->{'summary'}{'items'} };

    return ( $api_order->{'order_id'}, \@order_items );
}

sub set_url_after_checkout {
    my (%opts) = @_;

    my @missing_required_parms = grep { !length $opts{$_} } qw(
      order_id
      access_token
      url_after_checkout
    );

    if (@missing_required_parms) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_required_parms ] );
    }

    my $order_id           = $opts{'order_id'};
    my $access_token       = $opts{'access_token'};
    my $url_after_checkout = $opts{'url_after_checkout'};

    if ( $order_id !~ m<\A[0-9]+\z> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid item [asis,ID].', [$order_id] );
    }

    try {
        Cpanel::cPStore->new( api_token => $access_token )->post(
            "order/$order_id/callback",
            base_url => $url_after_checkout,
            passback => "order_id=$order_id",
        );
    }
    catch {
        if ( try { $_->isa('Cpanel::Exception::cPStoreError') } ) {
            _handle_market_disabled_exception($_);

            if ( try { $_->get('type') eq 'X::API::PermissionDenied' } ) {
                die Cpanel::Exception::External::create( 'Market::OrderNotFound', { provider => 'cPStore', order_id => $order_id } );
            }
        }

        local $@ = $_;
        die;
    };

    return 1;
}

=head2 perform_no_cost_checkout( %OPTS )

Performs a checkout using the no-cost payment method. This is only
valid for orders containing $0 items.

=head3 Arguments

%OPTS - A hash of options.

=over

=item

access_token (required) - The cPStore authentication token.

=item

order_id (required) - The order ID to check out.

=item

verification_code - If provided, this value will be sent as a means of account verification. This value is not required to complete the
checkout if the user account is already verified with the Store.

=item

send_verification - Sends a new verification code to the user if the
verification_code is not provided or is incorrect.

=back

=head3 Returns

1 if the checkout is successful. Throws otherwise.

=cut

sub perform_no_cost_checkout {
    my (%opts) = @_;

    for my $req (qw( access_token order_id )) {
        if ( !$opts{$req} ) {
            die Cpanel::Exception::create( 'MissingParameter', [ name => $req ] );
        }
    }

    my $cpstore  = Cpanel::cPStore->new( api_token => $opts{access_token} );
    my $order_id = $opts{order_id};
    my $endpoint = "order/$order_id/purchase/no-cost";

    my %payload;
    for my $key (qw(send_verification verification_code)) {
        $payload{$key} = $opts{$key} if defined $opts{$key};
    }

    my $response;
    try {
        $response = $cpstore->post(
            $endpoint,
            %payload,
        );
    }
    catch {
        if ( try { $_->isa('Cpanel::Exception::cPStoreError') } ) {
            _handle_market_disabled_exception($_);
            _handle_authentication_failure($_);

            my $error_type = $_->get('type');
            if ( $error_type eq 'X::Order::NotFound' ) {
                die Cpanel::Exception::External::create(
                    'Market::OrderNotFound',
                    {
                        provider => 'cPStore',
                        order_id => $order_id,
                    }
                );
            }

            # For no-cost purchases, this is a generic error used any time that
            # a customer needs to touch base with customer service to proceed.
            if ( $error_type eq 'X::PaymentFailed' ) {
                die Cpanel::Exception::External::create(
                    'Market::CustomerServiceRequired',
                    {
                        provider => 'cPStore',
                        order_id => $order_id,
                        mail_to  => get_support_uri_for_order( order_id => $order_id ),
                    }
                );
            }
        }

        local $@ = $_;
        die;
    };

    return 1;
}

my @_ERRORS_TO_TRAP_AND_REPORT = (

    Cpanel::Market::Provider::cPStore::Constants::FINAL_CPSTORE_CERTIFICATE_ERRORS(),

    # Unlike cPStore, we don’t report missing certs as an error.
    # NB: Later cPStore API versions will report not-found differently.
    #
    # UPDATE: As of August 2018, cPStore appears to send this error only
    # in rare cases; however, to be safe we are leaving this logic in.
    'CertificateNotFound',

    #This means that there’s a manual step required for fraud prevention.
    'RequiresApproval',
);

sub get_certificate_if_available {
    my ($order_item_id) = @_;

    if ( !length $order_item_id ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'order_item_id' ] );
    }

    if ( $order_item_id !~ m<\A[0-9]+\z> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid order item [asis,ID].', [$order_item_id] );
    }

    my $cpstore = Cpanel::cPStore->new();

    my ( $status_code, $status_message, $action_urls );

    my $data_hr;
    try {
        $data_hr = $cpstore->get("ssl/certificate/order/$order_item_id");

        _add_certificate_pem_if_applicable($data_hr) or do {
            my $status = $data_hr->{'status'};

            # Rejection or revocation from the CA isn’t a state that
            # cPStore considers to be a failure. We, though, do consider
            # that to be a failure.
            if ( $status eq 'rejected' || $status eq 'revoked' ) {
                $status_code    = "CA:$status";
                $status_message = $data_hr->{'status_message'};
            }
        };
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);

        for my $errcode (@_ERRORS_TO_TRAP_AND_REPORT) {
            if ( $_->get('type') eq "X::$errcode" ) {
                $status_code = $errcode;
                last;
            }
        }

        local $@ = $_;
        die if !$status_code;
    };

    return {
        certificate_pem       => $data_hr->{'certificate_pem'},
        status_code           => $status_code,
        status_message        => $status_message,
        encrypted_action_urls => $data_hr->{'actionUrls'},
    };
}

sub _get_dns_dcv_preparation_for_csr {
    require Cpanel::Market::Provider::cPStore::Utils;
    goto &Cpanel::Market::Provider::cPStore::Utils::get_dns_dcv_preparation_for_csr;
}

#csr, domains
sub install_dcv_dns_entries {
    my (@opts_kv) = @_;

    my ( $names_ar, $value ) = _get_dns_dcv_preparation_for_csr(@opts_kv);

    require Cpanel::Market::Provider::Utils;
    Cpanel::Market::Provider::Utils::install_dns_entries_of_type(
        [ map { [ $_ => $value ] } @$names_ar ],
        _DNS_DCV_RECORD_TYPE(),
    );

    return;
}

#csr, domains
sub remove_dcv_dns_entries {
    my (@opts_kv) = @_;

    my ($names_ar) = _get_dns_dcv_preparation_for_csr(@opts_kv);

    require Cpanel::Market::Provider::Utils;
    Cpanel::Market::Provider::Utils::remove_dns_names_of_type(
        $names_ar,
        _DNS_DCV_RECORD_TYPE(),
    );

    return;
}

sub get_certificate_status_details {
    my ($order_item_id) = @_;

    if ( !length $order_item_id ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'order_item_id' ] );
    }

    if ( $order_item_id !~ m<\A[0-9]+\z> ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid order item [asis,ID].', [$order_item_id] );
    }

    my $cpstore = Cpanel::cPStore->new();

    my $data_hr;
    my $status_code;

    try {
        $data_hr = $cpstore->get("ssl/certificate/order/$order_item_id?force=1");
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);

        for my $errcode (@_ERRORS_TO_TRAP_AND_REPORT) {
            if ( $_->get('type') eq "X::$errcode" ) {
                $status_code = $errcode;
                last;
            }
        }

        local $@ = $_;
        die if !$status_code;
    };

    $data_hr->{'actionUrls'} = decrypt_action_urls( _get_decrypt_csr_key($order_item_id), $data_hr->{'actionUrls'} );

    return {
        action_urls    => $data_hr->{'actionUrls'}     || {},
        status_details => $data_hr->{"status_details"} || {},
        domain_details => $data_hr->{"domain_details"} || []
    };
}

sub _get_decrypt_csr_key {
    my ($order_item_id) = @_;

    require Cpanel::SSL::PendingQueue;
    my $poll_db = Cpanel::SSL::PendingQueue->new();

    my $order_item = $poll_db->get_item_by_provider_order_item_id( 'cPStore', $order_item_id );
    my $parse      = $order_item->csr_parse();

    return get_key_with_text_for_csr($parse);
}

# Returns the SSLStorage hashref plus the key PEM.
# die()s if those can’t be gotten.
sub get_key_with_text_for_csr ($csr_parse) {

    require Cpanel::SSLStorage::User;
    my $ssl_storage_object = Cpanel::SSLStorage::User->new();

    my ( $ok, $key_hr ) = $ssl_storage_object->find_key_for_object($csr_parse);
    die $key_hr if !$ok;

    my $key_id = $key_hr->{'id'};

    my ( $get_key_status, $key ) = $ssl_storage_object->get_key_text($key_id);
    die $key if !$get_key_status;

    return ( $key_hr, $key );
}

sub decrypt_action_urls ( $key_parse, $key_pem, $action_urls_hr ) {    ## no critic qw(ManyArgs) - mis-parse
    require Cpanel::Market::Provider::cPStore::Decrypt;

    foreach my $url ( values %{$action_urls_hr} ) {
        $url = Cpanel::Market::Provider::cPStore::Decrypt::action_url( $key_parse, $key_pem, $url );
    }

    return $action_urls_hr;
}

sub undo_domain_control_validation_preparation {
    my (%opts) = @_;

    my $csr = $opts{'csr'} || die "Need “csr”!";

    #XXX: Later we’ll need to remove this so that root
    #can install SSL onto unowned docroots. But, for now …
    Cpanel::Security::Authz::verify_not_root();

    my ( undef, undef, $http_preparation_hr ) = _get_http_preparation_for_csr( $csr, SKIP_MISSING_DOCROOTS );

    for my $p ( values %$http_preparation_hr ) {
        unlink( $p->{'path'} ) or do {
            warn "unlink($p): $!" if !$!{'ENOENT'};
        };
    }

    return;
}

=head2 prepare_system_for_domain_control_validation( %OPTS )

This function will vary from module to module but, in general,
takes the passed “product_id” and “csr”, and from those determines
how to prepare the local system to validate the request.

In the case of cPStore/Sectigo, all we do is domain-control validation (DCV)
via HTTP or DNS, regardless of the kind of certificate we’re ordering, so we just
ignore “product_id” and create the relevant file on the filesystem.

Other CAs or SSL providers will likely either do the DCV differently (even
if it’s HTTP-based) and/or subject requests with different “product_id”
to different validation mechanisms.

XXX: It is very important that we get this right so that any future
3rd-party SSL providers can work within this framework. (NB: As of May 2018
there are no known 3rd-party Market SSL providers.)

Note that “domains”, if given, is guaranteed to be “leaf” authz domains.

=cut

sub prepare_system_for_domain_control_validation {
    my (%opts) = @_;

    #XXX: Later we’ll need to remove this so that root
    #can install SSL onto unowned docroots. But, for now …
    Cpanel::Security::Authz::verify_not_root();

    my $csr = $opts{'csr'} || die "Need “csr”!";

    my ( $relpath, $content, $preparation_hr ) = _get_http_preparation_for_csr( $csr, DIE_MISSING_DOCROOTS, $opts{'domains'} );

    my $queue = Cpanel::CommandQueue->new();

    # Paths are stored here as a means of deduplication; it’s possible
    # for multiple vhosts to share the same document root.
    my %paths_lookup;

    my @domains_to_dcv = keys %$preparation_hr;
    require Cpanel::DnsRoots;
    my $dns_lookups_hr = Cpanel::DnsRoots->new()->get_ip_addresses_for_domains(@domains_to_dcv);

    # The ordering by length is *probably* useless now. It formerly
    # allowed us to skip DCV on, e.g., “foo.example.com” if “example.com”
    # had already passed DCV, but as of late 2021 CAs no longer honor that
    # for HTTP DCV, so we can’t do that skip anymore. There’s no real
    # reason to *remove* it, though, and it does at least ensure a
    # consistent order.
    #
    for my $domain ( sort { length($a) <=> length($b) } @domains_to_dcv ) {
        my ($path) = @{ $preparation_hr->{$domain} }{'path'};

        $paths_lookup{$path} = undef;

        $queue->add(
            sub {

                #Set 0644 perms since the web server may not be
                #running as the user, in which case we will need
                #global read access.
                Cpanel::FileUtils::Write::overwrite( $path, $content, 0644 );

                _check_http_dcv_locally(
                    $domain,
                    $relpath,
                    $content,
                    $dns_lookups_hr,
                );
            },
            sub {
                Cpanel::Autodie::unlink_if_exists($path);
            },
            "Remove “$path”",
        );
    }

    $queue->run();

    return keys %paths_lookup;
}

#overridden in tests
sub _check_http_dcv_locally {
    require Cpanel::Market::Provider::cPStore::Utils;
    goto \&Cpanel::Market::Provider::cPStore::Utils::imitate_http_dcv_check_locally;
}

sub set_attribute_value {
    my (%opts) = @_;

    my @missing_required_parms = grep { !length $opts{$_} } qw(
      key
      value
      product_id
    );

    if (@missing_required_parms) {
        die Cpanel::Exception::create( 'MissingParameters', [ names => \@missing_required_parms ] );
    }

    my $item_hr = _get_product_list_entry_for_product_id( $opts{'product_id'} );

    if ( !exists $item_hr->{ $opts{'key'} } ) {
        die Cpanel::Exception::create( 'EntryDoesNotExist', 'The product with [asis,ID] “[_1]” does not have the attribute “[_2]”.', [ $opts{'product_id'}, $opts{'key'} ] );
    }

    if ( $item_hr->{'x_ssl_per_domain_pricing'} ) {
        if ( $opts{'key'} eq 'x_price_per_domain' ) {
            return _handle_price_per_domain_change( \%opts );
        }
        if ( $opts{'key'} eq 'x_price_per_wildcard_domain' ) {
            return _handle_price_per_domain_change( \%opts );
        }
    }

    #XXX
    die Cpanel::Exception::create( 'AttributeNotSet', 'The system does not recognize the attribute “[_1]” for the product with [asis,ID] “[_2]” as a settable attribute.', [ $opts{'key'}, $opts{'product_id'} ] );
}

#----------------------------------------------------------------------
#IMPORTANT!!!! The “read_only” flag will default to 1 via the calling layer,
#Cpanel::Market::get_market_provider_product_metadata().
#Every (production) call into this function needs to come from there.
sub get_product_metadata {
    my @products = get_products_list();

    my $metadata = {};

    for my $product (@products) {
        if ( $product->{'x_ssl_per_domain_pricing'} ) {
            $metadata->{ $product->{'product_id'} } = {
                attributes => {
                    x_price_per_domain => {
                        read_only => 0,
                    },
                    x_price_per_wildcard_domain => {
                        read_only => 0,
                    },
                },
            };
        }
    }

    return $metadata;
}

sub get_commission_id {

    my $cpstore = Cpanel::cPStore::LicenseAuthn->new();

    my $payload;

    try {
        $payload = $cpstore->get('ssl/payouts/recipient');
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);
        _handle_authentication_failure($_);

        local $@ = $_;
        die if $_->get('type') ne 'X::RecipientNotFound';
    };

    return $payload->{'email'};
}

sub set_commission_id {
    my (%opts) = @_;

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'commission_id' ] )                                      if !length $opts{'commission_id'};
    die Cpanel::Exception::create( 'InvalidParameter', 'You must enter a valid email address for the “[_1]” parameter.' ) if !Cpanel::Validate::EmailRFC::is_valid( $opts{'commission_id'} );

    my $cpstore = Cpanel::cPStore::LicenseAuthn->new();

    try {
        $cpstore->put(
            'ssl/payouts/recipient',
            email => $opts{'commission_id'}
        );
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);
        _handle_authentication_failure($_);
        if ( $_->get('type') eq 'X::User::NotFound' ) {
            die Cpanel::Exception::create( 'UserNotFound', 'The vendor has reported that the commission [asis,ID] “[_1]” does not exist.', [ $opts{'commission_id'} ] );
        }

        local $@ = $_;
        die;
    };

    return 1;
}

#----------------------------------------------------------------------

sub _add_certificate_pem_if_applicable {
    my ($data_hr) = @_;

    my $base64 = $data_hr->{'certificate'};

    if ($base64) {
        $data_hr->{'certificate_pem'} = Cpanel::SSL::Utils::base64_to_pem( $base64, 'CERTIFICATE' );

        return 1;
    }

    return 0;
}

#NB: This gets tested directly.
sub _get_http_preparation_for_csr {
    my ( $csr, $skip_missing_docroots, $domains_ar ) = @_;

    Cpanel::Context::must_be_list();

    require Cpanel::Market::Provider::cPStore::Utils;

    my ( $filename, $contents ) = Cpanel::Market::Provider::cPStore::Utils::get_domain_verification_filename_and_contents($csr);

    $domains_ar ||= do {
        my $csr_parse = Cpanel::OrDie::multi_return(
            sub { Cpanel::SSL::Utils::parse_csr_text($csr) },
        );

        $csr_parse->{'domains'};
    };

    my @wildcards = grep { Cpanel::WildcardDomain::Tiny::is_wildcard_domain($_) } @$domains_ar;
    die "HTTP DCV is wrong for wildcards (@wildcards)" if @wildcards;

    my %preparation_data;

    require Cpanel::Market::Provider::Utils;

    my %ensured_pki_val_dir_exists;

    my $pki_val_reldir = Cpanel::Market::Provider::cPStore::Constants::URI_DCV_RELATIVE_PATH();

    my $relative_path = "$pki_val_reldir/$filename";

    for my $domain (@$domains_ar) {
        my $docroot = Cpanel::Market::Provider::Utils::get_docroot_for_domain($domain);

        if ($docroot) {
            my $pki_val_absolute_dir = "$docroot/$pki_val_reldir";
            $pki_val_absolute_dir =~ tr{/}{}s;    # collapse duplicate /s

            $ensured_pki_val_dir_exists{$docroot} ||= do {
                Cpanel::Mkdir::ensure_directory_existence_and_mode( $pki_val_absolute_dir, 0755 );    # Must pass explict 0755 to ensure its set
                1;
            };

            $preparation_data{$domain} = {

                # This is the absolute path on the file system
                path => "$pki_val_absolute_dir/$filename",
            };
        }
        elsif ( !$skip_missing_docroots ) {

            # Formerly there was a warning here for the case where
            # a parent-domain docroot exists, which would allow
            # ancestor DCV substitution to secure a subdomain.
            # That’s no longer possible since HTTP DCV can’t
            # do ancestor DCV substitution anymore; thus, a missing
            # docroot is always a hard fail.

            die Cpanel::Exception::create( 'MissingDocumentRoot', 'No document root exists for “[_1]”.', [$domain] );
        }
    }

    return ( $relative_path, $contents, \%preparation_data );
}

sub _handle_price_per_domain_change {
    my ($opts) = @_;

    my ( $product_id, $attribute, $price_per_domain_pair ) = @{$opts}{qw( product_id key value )};

    if ( $opts->{'value'} !~ m<\A [0-9]+ (?: \.[0-9]{1,2})? \z>x ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The given value ([_1]) is not a valid [asis,USD] amount.', [ $opts->{'value'} ] );
    }

    #NB: This is the inverse of part of the transform done
    #in C::M::P::cPStore::ProductsCache.pm.

    my $divisor = even_commission_divisor();

    #Use 0.5 to work around invisible rounding error mumbo-jumbo.
    #e.g.: (10.2 * 100) % 12 = 11
    #
    #IEEE-754 is the suxxors...
    #
    my $price_per_domain_pair__pennies = sprintf( '%.02f', $price_per_domain_pair ) =~ s<\.><>r;

    if ( $price_per_domain_pair__pennies % $divisor ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The given price ($[_1]) must be a multiple of $[_2].', [ _format_dollars($price_per_domain_pair), _format_dollars( sprintf( '%02d', $divisor ) =~ s<([0-9]{2})\z><.$1>r ) ] );
    }

    my $cpstore = Cpanel::cPStore::LicenseAuthn->new();

    my $cpstore_short_name;

    my @products = @{ Cpanel::Market::Provider::cPStore::ProductsCache->load_with_short_name() };

    my $min_price_per_domain_pair;
    my $max_price_per_domain_pair;

    my $min_value_key = $attribute eq "x_price_per_wildcard_domain" ? 'x_price_per_wildcard_domain_minimum' : 'x_price_per_domain_minimum';
    my $max_value_key = $attribute eq "x_price_per_wildcard_domain" ? 'x_price_per_wildcard_domain_maximum' : 'x_price_per_domain_maximum';

    for my $prod (@products) {
        if ( $prod->{'product_id'} eq $product_id ) {
            $cpstore_short_name        = $prod->{'x_short_name'};
            $min_price_per_domain_pair = $prod->{$min_value_key};
            $max_price_per_domain_pair = $prod->{$max_value_key};
            last;
        }
    }

    #Should never happen.
    if ( !length $cpstore_short_name ) {
        die "Failed to locate a “short_name” for cPStore item_id “$product_id”!";
    }

    my $per_domain_short_name;
    if ( $attribute eq "x_price_per_wildcard_domain" ) {
        $per_domain_short_name = $Cpanel::Market::Provider::cPStore::Constants::SSL_SHORT_TO_WILDCARD_PRICING{$cpstore_short_name};

        #Shouldn’t happen ...
        if ( !length $per_domain_short_name ) {
            die Cpanel::Exception->create_raw("Failed to find per-wildcard-domain pricing item for “$cpstore_short_name”!");
        }
    }
    else {
        $per_domain_short_name = $Cpanel::Market::Provider::cPStore::Constants::SSL_SHORT_TO_PRICING{$cpstore_short_name};

        #Shouldn’t happen ...
        if ( !length $per_domain_short_name ) {
            die Cpanel::Exception->create_raw("Failed to find per-domain pricing item for “$cpstore_short_name”!");
        }
    }

    #Neither of these should happen in production because, as of 11.56, everything the cPStore
    #sells is a per-domain-priced SSL certificate.
    if ( !length $min_price_per_domain_pair ) {
        die Cpanel::Exception->create_raw("“$min_value_key” is missing!");
    }
    if ( !length $max_price_per_domain_pair ) {
        die Cpanel::Exception->create_raw("“$max_value_key” is missing!");
    }

    if ( $price_per_domain_pair < $min_price_per_domain_pair ) {
        die Cpanel::Exception::create( 'InvalidParameter', '$[_1] is too low of a price. The minimum price per domain for this product is $[_2].', [ _format_dollars($price_per_domain_pair), _format_dollars($min_price_per_domain_pair) ] );
    }
    elsif ( $price_per_domain_pair > $max_price_per_domain_pair ) {
        die Cpanel::Exception::create( 'InvalidParameter', '$[_1] USD is too high. This product’s price may not exceed $[_2] USD per domain.', [ _format_dollars($price_per_domain_pair), _format_dollars($max_price_per_domain_pair) ] );
    }

    # Price should be sent as half for normal domains, to account for www vs main domain
    # In the case of wildcard, the price is the total price for the wild card domain, so we don't divide by 2
    my $domain_price = $attribute eq "x_price_per_wildcard_domain" ? $price_per_domain_pair : $price_per_domain_pair / 2;

    try {
        $cpstore->put(
            "ssl/certificate/price/$per_domain_short_name",
            price => $domain_price,
        );
    }
    catch {
        local $@ = $_;
        die if !try { $_->isa('Cpanel::Exception::cPStoreError') };
        _handle_market_disabled_exception($_);
        _handle_authentication_failure($_);

        local $@ = $_;
        die;
    };

    # Attribute change stored in adjustments DB via the Whostmgr::API::1::set_market_product_attribute
    # Please call Cpanel::Market::adjust_market_product_attribute if we need to set this elsewhere.

    Cpanel::Market::Provider::cPStore::ProductsCache->delete();

    return 1;
}

sub _format_dollars {
    require Cpanel::Market::Provider::cPStore::Utils;
    goto \&Cpanel::Market::Provider::cPStore::Utils::format_dollars;
}

sub _handle_authentication_failure {
    my ($cpstore_exception) = @_;

    if ( $cpstore_exception->get('type') eq 'X::AuthenticationFailure' ) {
        die Cpanel::Exception::create( 'AuthenticationFailed', 'The system could not connect to the [asis,cPanel Store] due to an error: “[_1]”. Run the “[_2]” command.', [ $cpstore_exception->get('message'), '/usr/local/cpanel/cpkeyclt' ] );
    }
}

sub _handle_market_disabled_exception {
    my ($cpstore_exception) = @_;

    if ( $cpstore_exception->get('type') eq 'X::MarketDisabled' ) {
        require Cpanel::Market;

        # The store says the cPStore market module is disabled at the license level, so disable it on disk:
        try {
            # Failures here aren't as important as telling the frontend that we're disabled.
            Cpanel::Market::disable_provider('cPStore');
        };

        die Cpanel::Exception::External::create( 'Market::Disabled', { provider => 'cPStore' } );
    }
}

1;
