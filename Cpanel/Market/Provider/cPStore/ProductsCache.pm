package Cpanel::Market::Provider::cPStore::ProductsCache;

# cpanel - Cpanel/Market/Provider/cPStore/ProductsCache.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# NOTE TODO: The versioning stuff here could be useful as a general-use
# module, e.g., Cpanel::CacheFile::Versioned. Part of the trouble there
# will be separating the versioning logic out from the authz.
#----------------------------------------------------------------------

use strict;
use warnings;

use parent qw( Cpanel::CacheFile );

use Try::Tiny;

use Cpanel::Exception                            ();
use Cpanel::Exception::External                  ();
use Cpanel::cPStore                              ();
use Cpanel::LoadFile                             ();
use Cpanel::ConfigFiles                          ();
use Cpanel::HTTP::QueryString                    ();
use Cpanel::LocaleString                         ();
use Cpanel::Market::Provider::cPStore::Constants ();
use Cpanel::Market::Tiny                         ();
use Cpanel::SSL::Providers::Sectigo              ();
use Cpanel::Version                              ();

#exposed for testing
#v2 added the encoded locale string
#v3 added x_supports_dns_dcv
our $_SCHEMA_VERSION = 3;

our $MAXIMUM_PRICE_WE_CAN_EVER_CHARGE_FOR_ANYTHING = 1_000_000;
our $SUPPORTED_CPSTORE_VERSION                     = '4';

#called from test
sub _PATH {
    return "$Cpanel::Market::Tiny::CPMARKET_CONFIG_DIR/cpstore_products.cache";
}

sub _TTL { return 86400 }    #one day

#Anyone can read, but only root can write.
sub _MODE { return 0644 }

#----------------------------------------------------------------------

#i.e., a multiple of the minimum price beyond which we consider
#the price to have been set unreasonably high, and error out.
my $MAX_PRICE_MULTIPLE = 10;

#overridden in tests
sub _fetch_from_cpstore {

    # Using the URL provided by [~j.b] on 4.2.16 in Cobra hipchat
    # This change cannot go live until AA-2083 is live
    my $query_str = Cpanel::HTTP::QueryString::make_query_string(
        version => Cpanel::Version::getversionnumber(),
    );

    return Cpanel::cPStore->new()->get("products/cpanel/$SUPPORTED_CPSTORE_VERSION?$query_str");
}

#An ugly hack to get versioning.
our $__LOADED_FRESH;

sub _LOAD_FRESH {
    my ($class) = @_;

    $__LOADED_FRESH = 1;
    return _load_fresh_as_user() if $>;

    my $products_list;
    try {
        $products_list = _fetch_from_cpstore();
    }
    catch {
        my $exception = $_;
        local $@ = $exception;
        die if !try { $exception->isa('Cpanel::Exception::cPStoreError') };

        my %cacheable_type = map { $_ => undef } qw{ X::ItemNotFound X::MarketDisabled X::UnlicensedIP };
        my $type           = $exception->get('type');

        if ( exists $cacheable_type{$type} ) {

            # Cache the exception so it can be rethrown next time and not hammer the store.
            try {
                $class->save( [], '_exception' => { 'cache_time' => time(), 'args' => _get_cpstore_exception_args_ref($exception) } );
            }
            catch {
                local $@ = $_;
                warn;
            };
        }
        _handle_market_disabled_exception($exception);

        die;
    };

    return _get_fixed_product_list($products_list);
}

sub load {
    my ($class) = @_;

    my $products_ar = $class->load_with_short_name();

    delete $_->{'x_short_name'} for @$products_ar;

    return $products_ar;
}

sub _reconstitute_locale_strings {
    my ($products_ar) = @_;

    for my $prod (@$products_ar) {
        next if !$prod->{'x_identity_verification'};
        for my $iv_hr ( @{ $prod->{'x_identity_verification'} } ) {
            for my $attr (qw( label description )) {
                next if !length $iv_hr->{$attr};
                $iv_hr->{$attr} = Cpanel::LocaleString->thaw( $iv_hr->{$attr} );
            }

            if ( $iv_hr->{'options'} ) {
                for my $opt ( @{ $iv_hr->{'options'} } ) {
                    $opt->[1] = Cpanel::LocaleString->thaw( $opt->[1] );
                }
            }
        }
    }

    return;
}

#Only should be called for price checks. (Normally? Other uses?)
sub load_with_short_name {
    my ($class) = @_;

    local $__LOADED_FRESH;

    my $load = $class->SUPER::load();

    return $load if $__LOADED_FRESH;    #It’s already saved.

    if ( $load->{'_exception'} ) {
        my $exception = _reconstitute_cached_cpstore_exception( $load->{'_exception'} );
        _handle_market_disabled_exception($exception);
        local $@ = $exception;
        die;
    }

    if ( $load->{'_schema'} == $_SCHEMA_VERSION ) {
        _reconstitute_locale_strings( $load->{'_products'} );

        return $load->{'_products'};
    }

    $load = $class->_LOAD_FRESH();
    $class->save($load);

    return $load;
}

sub save {
    my ( $self, $new_data, @additional_cache_data ) = @_;

    #Only try to save() when running as root.
    return undef if $>;

    require Cpanel::Market::Tiny;
    Cpanel::Market::Tiny::create_market_directory_if_missing();

    my $serialize = Cpanel::LocaleString->set_json_to_freeze();

    return $self->SUPER::save(
        {
            _schema   => $_SCHEMA_VERSION,
            _products => $new_data,
            @additional_cache_data,
        },
    );
}

sub _load_fresh_as_user {
    require Cpanel::AdminBin::Call;
    return Cpanel::AdminBin::Call::call(
        'Cpanel',
        'market',
        'CACHE_CPSTORE_PRODUCTS',
    );
}

#----------------------------------------------------------------------

#The cPStore gives us a less-than-useful product list; this layer
#transmogrifies it into something “friendlier”.
sub _get_fixed_product_list {
    my ($products_ar) = @_;

    my %short_name_index = map { $_->{'short_name'} => $_ } @$products_ar;

    my @ret_products;

    for my $p_hr (@$products_ar) {
        next if $p_hr->{'product_group'} eq 'ssl-component-pricing';

        push @ret_products, $p_hr;

        #----------------------------------------------------------------------
        # cPStore uses the key “item_id” to refer to an item in a catalog.
        # Because we also have “Order ID” and “Order Item ID”, we want to avoid
        # calling anything user-facing an “Item ID”. To stem confusion on this
        # end, then, we’ll convert “item_id” into “product_id”, consistent with
        # the user-facing term “Product ID”.
        #
        $p_hr->{'product_id'} = delete $p_hr->{'item_id'};

        my $short_name = delete $p_hr->{'short_name'};

        $p_hr->{'x_certificate_term'} = $p_hr->{'certificate_term'} ? [ $p_hr->{'certificate_term'}, 'year' ] : [ 1, 'year' ];

        #remove the certificate term since it's stored in correct form above.
        delete $p_hr->{'certificate_term'};

        if ( ( $p_hr->{'product_group'} || q<> ) =~ m<\Assl-certificate-(dv|ov|ev)\z> ) {
            my $validation_level = $1;

            my $per_domain_item_hr         = $short_name_index{ $Cpanel::Market::Provider::cPStore::Constants::SSL_SHORT_TO_PRICING{$short_name} };
            my $wildcard_pricing_shortname = $Cpanel::Market::Provider::cPStore::Constants::SSL_SHORT_TO_WILDCARD_PRICING{$short_name};
            my $per_domain_wc_item_hr      = $wildcard_pricing_shortname ? $short_name_index{$wildcard_pricing_shortname} : {};

            my $domain_price           = 2 * $per_domain_item_hr->{'price'};
            my $wildcard_price         = $per_domain_wc_item_hr->{'price'};
            my $minimum_price          = $per_domain_item_hr->{'minimum_server_price'};
            my $minimum_wildcard_price = $per_domain_wc_item_hr->{'minimum_server_price'};

            $minimum_price &&= $minimum_price * 2;

            #This *probably* won’t be needed; however, if we ever allow free
            #certificates using this mechanism, this provides a fail-safe.
            my $max_price          = $per_domain_item_hr->{'maximum_server_price'};
            my $max_wildcard_price = $per_domain_wc_item_hr->{'maximum_server_price'};
            $max_price &&= $max_price * 2;

            if ( !$max_price && $minimum_price ) {
                $max_price = $minimum_price * $MAX_PRICE_MULTIPLE;
            }

            if ( !$max_wildcard_price && $minimum_wildcard_price ) {
                $max_wildcard_price = $minimum_wildcard_price * $MAX_PRICE_MULTIPLE;
            }

            if ( !defined($max_price) || $max_price > $MAXIMUM_PRICE_WE_CAN_EVER_CHARGE_FOR_ANYTHING ) {
                $max_price = $MAXIMUM_PRICE_WE_CAN_EVER_CHARGE_FOR_ANYTHING;
            }

            if ( !defined($max_wildcard_price) || $max_wildcard_price > $MAXIMUM_PRICE_WE_CAN_EVER_CHARGE_FOR_ANYTHING ) {
                $max_wildcard_price = $MAXIMUM_PRICE_WE_CAN_EVER_CHARGE_FOR_ANYTHING;
            }

            my %augment = (
                product_group => 'ssl_certificate',
                price         => undef,

                #NOTE: The following are specific to this product_group
                #and so are named with an “x_” prefix.
                x_ssl_per_domain_pricing   => 1,
                x_price_per_domain         => $domain_price,
                x_price_per_domain_minimum => $minimum_price,
                x_price_per_domain_maximum => $max_price,

                (
                    defined $wildcard_price
                    ? (
                        x_price_per_wildcard_domain         => $wildcard_price,
                        x_price_per_wildcard_domain_minimum => $minimum_wildcard_price,
                        x_price_per_wildcard_domain_maximum => $max_wildcard_price,
                        x_wildcard_parent_domain_free       => 1,
                      )
                    : ()
                ),

                #Needed for price changes. It gets stripped out before
                #we actually send this to API consumers.
                x_short_name => $short_name,

                #time after which to warn the customer that the certificate
                #should have been delivered by now
                x_warn_after => 86400 * 7,

                #Comodo doesn’t do HTTP redirects for DCV.
                x_max_http_redirects => Cpanel::SSL::Providers::Sectigo::HTTP_DCV_MAX_REDIRECTS(),

                x_validation_type => $validation_level,

                x_supports_dns_dcv => 1,

                #OV and EV certs are charged right away;
                #DV certs are charged only when the customer receives
                #the certificate.
                x_payment_trigger => ( $validation_level eq 'dv' ) ? 'issuance' : 'checkout',
            );

            my $iden_ver;
            if ( $validation_level eq 'ov' ) {
                $iden_ver = [ Cpanel::Market::Provider::cPStore::Constants::get_ov_identity_verification_data() ];
            }
            elsif ( $validation_level eq 'ev' ) {
                $iden_ver = [ Cpanel::Market::Provider::cPStore::Constants::get_ev_identity_verification_data() ];
            }

            $augment{'x_identity_verification'} = $iden_ver;

            try {
                require MIME::Base64;
                require Cpanel::ConfigFiles;
                require Cpanel::LoadFile;

                my $path = "$Cpanel::ConfigFiles::CPANEL_ROOT/img-sys/";
                if ( $short_name =~ m<\Acomodo> ) {
                    $path .= 'sectigo_logo_mark_color.svg';
                }
                elsif ( $short_name =~ m<\Acpanel> ) {
                    $path .= 'cp-logo-RGB-v42015.svg';
                }
                else {
                    undef $path;
                }

                if ($path) {
                    my $content = Cpanel::LoadFile::load($path);
                    %augment = (
                        %augment,
                        icon_mime_type => 'image/svg+xml',
                        icon           => MIME::Base64::encode_base64($content),
                    );

                    $augment{'icon'} =~ s<\s+><>g;
                }

            }
            catch {
                local $@ = $_;
                warn;
            };

            @{$p_hr}{ keys %augment } = values %augment;
        }

        $p_hr->{'price_unit'} ||= 'USD';
    }

    return \@ret_products;
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

        # A 'cache_time' value will exist if we're rethrowing a cached exception and this needs to be passed on.
        my $cache_time = $cpstore_exception->get('cache_time');
        die Cpanel::Exception::External::create(
            'Market::Disabled',
            {
                provider => 'cPStore',
                ( length $cache_time ? ( 'cache_time' => $cache_time ) : () ),
            }
        );
    }
    return;
}

sub _get_cpstore_exception_args_ref {
    my ($cpstore_exception) = @_;
    return [ map { $_ => $cpstore_exception->get($_) } qw{ request type message data } ];
}

sub _reconstitute_cached_cpstore_exception {
    my ($cache_hr) = @_;
    return Cpanel::Exception::create(
        'cPStoreError',
        [
            'cache_time' => $cache_hr->{'cache_time'},
            @{ $cache_hr->{'args'} },
        ]
    );
}

1;
