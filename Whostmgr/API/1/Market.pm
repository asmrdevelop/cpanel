package Whostmgr::API::1::Market;

# cpanel - Whostmgr/API/1/Market.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Whostmgr::API::1::Market - API module for Marketplace functions.

=head1 SYNOPSIS

    use Whostmgr::API::1::Market;
    use Whostmgr::API::1::Utils::Metadata;
    my $metadata = bless( {}, "Whostmgr::API::1::Utils::Metadata" );

    Whostmgr::API::1::Market::purchase_a_trial({
        login_token => "663e3030-b0ea-11ea-b25f-c07f3fb29d3d",
        provider => "cPStore",
    }, $metadata);

=head1 DESCRIPTION

This module provides API methods to interact with Market providers.

=head1 METHODS

This module provides API methods to interact with Market providers.

=cut

use strict;
use warnings;

use Cpanel::DIp::MainIP     ();
use Cpanel::Exception       ();
use Cpanel::Market          ();
use Cpanel::NAT             ();
use Cpanel::OSSys::Env      ();
use Cpanel::Market::Tiny    ();
use Whostmgr::API::1::Utils ();

use Try::Tiny;

use constant NEEDS_ROLE => {
    disable_market_provider                => undef,
    enable_market_provider                 => undef,
    get_adjusted_market_providers_products => undef,
    get_login_url                          => undef,
    get_market_providers_commission_config => undef,
    get_market_providers_list              => undef,
    get_market_providers_product_metadata  => undef,
    get_market_providers_products          => undef,
    purchase_a_license                     => undef,
    purchase_a_trial                       => undef,
    set_market_product_attribute           => undef,
    set_market_provider_commission_id      => undef,
    validate_login_token                   => undef,
};

sub _provider_ns {
    my ($args) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    return Cpanel::Market::get_and_load_module_for_provider($provider);
}

#XXX TODO: Make this a more general configuration-getter.
sub get_market_providers_list {
    my ( $args, $metadata ) = @_;

    my @providers = Cpanel::Market::Tiny::get_provider_names();

    my %enabled;
    @enabled{ Cpanel::Market::get_enabled_provider_names() } = ();

    my @combined_providers;

    for my $provider (@providers) {
        my $supports_commission = _do_provider_if_function_available( { provider => $provider }, 'provider_supports_commission' ) ? 1 : 0;
        my $commission_divisor  = _do_provider_if_function_available( { provider => $provider }, 'even_commission_divisor' ) || 1;
        push @combined_providers, {
            name                => $provider,
            display_name        => scalar Cpanel::Market::get_provider_display_name($provider),
            enabled             => exists $enabled{$provider} ? 1 : 0,
            supports_commission => $supports_commission,
            ( $supports_commission ? ( even_commission_divisor => $commission_divisor ) : () ),
        };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@combined_providers };
}

sub get_market_providers_products {
    my ( $args, $metadata ) = @_;

    my @providers = Cpanel::Market::Tiny::get_provider_names();
    my @products;

    my @errors;
    for my $provider (@providers) {
        try {
            my $provider_namespace = _provider_ns( { 'provider' => $provider } );
            my @provider_products  = $provider_namespace->can('get_products_list')->();

            my $provider_display_name = Cpanel::Market::get_provider_display_name($provider);
            for my $product (@provider_products) {
                $product->{provider_name}         = $provider;
                $product->{provider_display_name} = $provider_display_name;
            }

            push @products, @provider_products;
        }
        catch {
            push @errors, $_;
        };
    }

    if (@errors) {
        if ( ( scalar @errors ) < ( scalar @providers ) ) {
            $metadata->{warnings} = [ map { Cpanel::Exception::get_string($_) } @errors ];
        }
        else {
            die Cpanel::Exception::create( 'Collection', [ exceptions => \@errors ] );
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);
    return { products => \@products };
}

sub get_adjusted_market_providers_products {
    my ( $args, $metadata ) = @_;

    my %data = Cpanel::Market::get_adjusted_market_providers_products();
    my @flattened_data;
    for my $provider ( keys %data ) {
        my $provider_display_name = Cpanel::Market::get_provider_display_name($provider);
        for my $item ( @{ $data{$provider} } ) {
            $item->{provider_name}         = $provider;
            $item->{provider_display_name} = $provider_display_name;
            push @flattened_data, $item;
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { products => \@flattened_data };
}

sub get_market_providers_product_metadata {
    my ( $args, $api_metadata ) = @_;

    my $product_metadata_hr = Cpanel::Market::get_market_providers_product_metadata();

    my @product_metadata = ();
    for my $provider ( keys %$product_metadata_hr ) {
        my $provider_display_name = Cpanel::Market::get_provider_display_name($provider);
        for my $product_id ( keys %{ $product_metadata_hr->{$provider} } ) {
            push @product_metadata, {
                %{ $product_metadata_hr->{$provider}{$product_id} },
                'product_id'            => $product_id,
                'provider_name'         => $provider,
                'provider_display_name' => $provider_display_name,
            };
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($api_metadata);

    return { product_metadata => \@product_metadata };
}

sub get_market_providers_commission_config {
    my ( $args, $metadata ) = @_;

    my $config           = Cpanel::Market::get_market_commission_config();
    my @provider_configs = ();

    for my $provider ( keys %$config ) {
        my $provider_display_name = Cpanel::Market::get_provider_display_name($provider);
        push @provider_configs, {
            'provider_name'         => $provider,
            'provider_display_name' => $provider_display_name,
            map {
                my $hash_name = "${_}_commission_id";
                exists $config->{$provider}{'commission_id'}{$_} ? ( $hash_name => $config->{$provider}{'commission_id'}{$_} ) : ()
            } qw( remote local )
        };
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { 'payload' => \@provider_configs };
}

sub set_market_provider_commission_id {
    my ( $args, $metadata ) = @_;

    my $provider      = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );
    my $commission_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'commission_id' );

    Cpanel::Market::set_market_provider_commission_id( $provider, $commission_id );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub set_market_product_attribute {
    my ( $args, $metadata ) = @_;

    my $product_id = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'product_id' );
    my $attribute  = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'attribute' );
    my $value      = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'value' );
    my $provider   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    # Recommended and enabled are attributes we inject, so we handle them a bit differently (for now?)
    if ( $attribute eq 'recommended' ) {
        if ( !$value || !length $value ) {
            Cpanel::Market::disable_market_product_recommendation( $provider, $product_id );
        }
        else {
            Cpanel::Market::enable_market_product_recommendation( $provider, $product_id );
        }
    }
    elsif ( $attribute eq 'enabled' ) {
        if ( !$value || !length $value ) {
            Cpanel::Market::disable_market_product( $provider, $product_id );
        }
        else {
            Cpanel::Market::enable_market_product( $provider, $product_id );
        }
    }
    else {
        my $perl_ns = Cpanel::Market::get_and_load_module_for_provider($provider);

        if ( my $func_ref = $perl_ns->can('set_attribute_value') ) {
            $func_ref->( 'product_id' => $product_id, 'key' => $attribute, 'value' => $value );
            Cpanel::Market::adjust_market_product_attribute( $args->{'provider'}, $product_id, $attribute, $value );
        }
        else {
            die Cpanel::Exception::create( 'AttributeNotSet', 'The provider module “[_1]” does not allow changes to attribute values.', $provider );
        }
    }

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub enable_market_provider {
    my ( $args, $metadata ) = @_;

    return _toggle_provider( $args, $metadata, 'enable_provider' );
}

sub disable_market_provider {
    my ( $args, $metadata ) = @_;

    return _toggle_provider( $args, $metadata, 'disable_provider' );
}

sub get_login_url {
    my ( $args, $metadata ) = @_;

    my ($url_after_login) = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'url_after_login' );

    my @urls = ();

    push @urls, _do_provider( $args, 'get_login_url', $url_after_login );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@urls };
}

sub validate_login_token {
    my ( $args, $metadata ) = @_;

    my $login_token     = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'login_token' );
    my $url_after_login = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'url_after_login' );

    my @tokens = ();
    push @tokens, _do_provider( $args, 'validate_login_token', $login_token, $url_after_login );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@tokens };
}

sub _get_license_products {
    my $products_list;

    require Cpanel::cPStore;
    try {
        $products_list = Cpanel::cPStore->new()->get("products/cpstore");
    };

    return [ grep { $_->{'product_group'} =~ m/^license-/ } @$products_list ];
}

sub purchase_a_license {
    my ( $args, $metadata ) = @_;

    my $login_token = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'login_token' );

    my $redirect_url = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'url_after_checkout' );

    my $is_upgrade = Whostmgr::API::1::Utils::get_length_argument( $args, 'upgrade' );

    my $license_products = _get_license_products();

    my $envtype     = Cpanel::OSSys::Env::get_envtype();
    my $item_id     = $envtype eq 'standard' ? '105' : '109';
    my ($item_desc) = grep { $_->{item_id} eq $item_id } @$license_products;
    $item_desc->{product_id} = $item_desc->{item_id};

    my $mainserverip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
    require Cpanel::Config::LoadUserDomains::Count;
    my $user_count = Cpanel::Config::LoadUserDomains::Count::counttrueuserdomains();

    my $license_item = {
        'product_id' => $item_id,
        'ips'        => [$mainserverip],
        'user_count' => $user_count,
    };
    $license_item->{'upgrade'} = 'true' if defined $is_upgrade && $is_upgrade eq '1';

    my ( $order_id, $order_items_ar ) = _do_provider(
        $args, 'create_shopping_cart',
        access_token       => $login_token,
        url_after_checkout => $redirect_url,
        items              => [
            $license_item,
        ]
    );

    my @checkout_urls = _do_provider( $args, 'get_checkout_url_whm', $order_id );

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return { payload => \@checkout_urls };
}

=head2 purchase_a_trial( $ARGS, $METADATA )

Adds a standard trial license for the current IP to a new order and
performs a no-cost checkout.

=head3 Arguments

$ARGS - A hash ref of arguments to the API call.

=over

=item

login_token (required) - The Market provider's authentication token.

=item

provider (required) - The Market provider's key.

=item

checkout_args - A hash ref of arguments to send to the provider's checkout method. The specific args required, if any, will be specific to each provider.

=back

$METADATA - A standard WHM API 1 metadata object.

=head3 Returns

A hash ref containing:

=over

=item

licensed_ip - The IP that was licensed for the trial.

=back

=cut

sub purchase_a_trial {
    my ( $args, $metadata ) = @_;

    my $login_token   = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'login_token' );
    my $checkout_args = $args->{checkout_args} || {};

    my $mainserverip = Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );

    require Cpanel::Market::Provider::cPStore::Constants;
    my $license_item = {
        product_id => $Cpanel::Market::Provider::cPStore::Constants::ITEM_IDS->{standard_trial_license},
        ip_address => $mainserverip,
    };

    my ( $order_id, $order_items_ar ) = _do_provider(
        $args, 'create_shopping_cart',
        access_token => $login_token,
        items        => [
            $license_item,
        ],
    );

    my $checkout_error;
    try {
        _do_provider(
            $args, 'perform_no_cost_checkout',
            access_token => $login_token,
            order_id     => $order_id,
            %$checkout_args
        );
    }
    catch {
        $checkout_error = $_;
    };

    return _create_typed_error_if_typed_or_die( $checkout_error, $metadata ) if $checkout_error;

    $metadata->set_ok();
    return {
        licensed_ip => $mainserverip,
    };
}

# Errors returned from market providers often have type information, which is important
# to clients. If we want to return that data, we cannot throw the exception in the typical
# way, as WHM API's wrapper will catch it and only return the error string.
#
# This helper function returns typed error information for inclusion with the return data
# if there is type data. If there is no type information, it will simply die and WHM API
# will handle it normally.
sub _create_typed_error_if_typed_or_die {
    my ( $error, $api_metadata ) = @_;

    require Cpanel::APICommon::Error;

    my $type = Cpanel::APICommon::Error::get_type($error);
    die $error if !$type;    # No type information available, so just let the default API error handling tackle it

    require Scalar::Util;

    if ( Scalar::Util::blessed($error) && $error->isa("Cpanel::Exception") ) {
        $api_metadata->set_not_ok( $error->to_string() );
        my $error_metadata = $error->get_all_metadata();
        return Cpanel::APICommon::Error::convert_to_payload( $type, %$error_metadata );
    }
    else {
        my $error_str = $error->can('error') && $error->error() || $error;
        $api_metadata->set_not_ok($error_str);
        return Cpanel::APICommon::Error::convert_to_payload( $type, {} );
    }
}

sub _toggle_provider {
    my ( $args, $metadata, $what_to_do ) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'name' );

    Cpanel::Market->can($what_to_do)->($provider);

    Whostmgr::API::1::Utils::set_metadata_ok($metadata);

    return;
}

sub _do_provider {
    my ( $args, $func, @args ) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    my $perl_ns = Cpanel::Market::get_and_load_module_for_provider($provider);

    return $perl_ns->can($func)->(@args);
}

sub _do_provider_if_function_available {
    my ( $args, $func, @args ) = @_;

    my $provider = Whostmgr::API::1::Utils::get_length_required_argument( $args, 'provider' );

    my $perl_ns = Cpanel::Market::get_and_load_module_for_provider($provider);

    if ( my $func_ref = $perl_ns->can($func) ) {
        return $func_ref->(@args);
    }

    return;
}

1;
