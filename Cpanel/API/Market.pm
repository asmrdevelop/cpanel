package Cpanel::API::Market;

# cpanel - Cpanel/API/Market.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel                                   ();
use Cpanel::API                              ();
use Cpanel::Logger                           ();
use Cpanel::Market::Provider::cPStore        ();
use Cpanel::Market::Provider::cPStore::Utils ();

use Try::Tiny;

use Cpanel::AdminBin::Call    ();
use Cpanel::cPStore           ();
use Cpanel::Exception         ();
use Cpanel::HTTP::QueryString ();
use Cpanel::JSON              ();
use Cpanel::LoadModule        ();
use Cpanel::Market            ();
use Cpanel::Security::Authz   ();
use Cpanel::SSL::PendingQueue ();
use Cpanel::NAT               ();
use Cpanel::DIp::MainIP       ();

#my $POLL_INTERVAL = 10;
my $POLL_INTERVAL = 3;            #for testing
my $MAX_POLL_TIME = 5 * 86400;    #5 days

my $market_feature = {
    needs_feature => "market",
};

my $market_tls_wizard_feature = {
    needs_feature => { match => 'all', features => [qw(market tls_wizard)] },
};

our %API = (
    get_providers_list                    => $market_feature,
    get_login_url                         => $market_feature,
    validate_login_token                  => $market_feature,
    process_ssl_pending_queue             => $market_feature,
    cancel_pending_ssl_certificate        => $market_feature,
    get_provider_specific_dcv_constraints => $market_tls_wizard_feature,
    get_all_products                      => $market_feature,
    create_shopping_cart                  => $market_feature,
    set_status_of_pending_queue_items     => $market_tls_wizard_feature,
    get_pending_ssl_certificates          => $market_tls_wizard_feature,
    request_ssl_certificates              => {
        needs_feature => { match => 'all', features => [qw(market sslinstall tls_wizard)] },
    },
    set_url_after_checkout           => $market_tls_wizard_feature,
    get_ssl_certificate_if_available => $market_tls_wizard_feature,
    get_certificate_status_details   => $market_tls_wizard_feature,
);

sub _do_provider {
    my ( $args, $func, @args ) = @_;

    my ($provider) = $args->get_length_required('provider');

    my $perl_ns = Cpanel::Market::get_and_load_module_for_provider($provider);

    my $func_cr = $perl_ns->can($func) or die "“$provider” has no method “$func”!";

    return $func_cr->(@args);
}

=head1 FUNCTIONS

=cut

sub get_providers_list {
    my ( $args, $result ) = @_;

    my @names = Cpanel::Market::get_enabled_provider_names();

    $result->data(
        [
            map {
                {
                    name         => $_,
                    display_name => Cpanel::Market::get_provider_display_name($_),
                }
            } @names,
        ]
    );

    return 1;
}

#inputs: provider, url_after_login
#
#The response is just the URL. This URL should be a form that, upon
#successful login, redirects the browser to “url_after_login” with a “code”
#in the URL’s query string; that “code” will be the “login_token” that
#goes into validate_login_token.
#
#NOTE: You may include form parameters in “url_after_login” as a means of
#preserving state.
#
sub get_login_url {
    my ( $args, $result ) = @_;

    my ($url_after_login) = $args->get_length_required('url_after_login');

    $result->data( _do_provider( $args, 'get_login_url', $url_after_login ) );

    return 1;
}

#returns a hashref:
#
#{
#   access_token => '...',  #i.e., the access token
#   refresh_token => '...', #not used currently
#}
#
sub validate_login_token {
    my ( $args, $result ) = @_;

    my $login_token     = $args->get_length_required('login_token');
    my $url_after_login = $args->get_length_required('url_after_login');

    $result->data( _do_provider( $args, 'validate_login_token', $login_token, $url_after_login ) );

    return 1;
}

sub process_ssl_pending_queue {
    my ( $args, $result ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::PendingQueue::Run');

    my @result = Cpanel::SSL::PendingQueue::Run::process();

    #The CSR parse is a very proprietary, “unpolished” data structure.
    #Unless people really want it, let’s save ourselves the documentation
    #and maintenance overhead.
    delete $_->{'csr_parse'} for @result;

    $result->data( \@result );

    return 1;
}

#inputs: provider, order_item_id
#
# Cancels an ssl certificate from the pending queue if it matches
# the provider and order_item_id.
#
# This does not currently cancel anything on the store side directly;
# however, removing the pending queue entry also removes the domain-control
# validation (DCV) file, which will prevent the provider’s CA from verifying
# domain ownership, which will prevent issuance of the certificate, which, for
# cPStore, will prevent the customer’s credit card from being charged.
#
#Returns a list of the certs removed from the queue. The structure
#is identical to get_pending_ssl_certificates()’s return structure.
sub cancel_pending_ssl_certificate {
    my ( $args, $result ) = @_;

    my $provider      = $args->get_length_required('provider');
    my $order_item_id = $args->get_length_required('order_item_id');

    my $poll_db     = Cpanel::SSL::PendingQueue->new();
    my @queue_items = $poll_db->read();

    my @removed;

    for my $item (@queue_items) {
        if ( $item->order_item_id eq $order_item_id && $provider eq $item->provider ) {
            $poll_db->remove_item($item);
            push @removed, _pending_item_to_return($item);
            last;
        }
    }

    $poll_db->finish();

    $result->data( \@removed );

    if ( @removed && @removed == @queue_items ) {
        local $@;
        my $ok = eval {
            Cpanel::AdminBin::Call::call(
                'Cpanel',
                'ssl_call',
                'STOP_POLLING',
            );
            1;
        };
        $result->raw_message( Cpanel::Exception::get_string($@) ) if !$ok;
    }

    return 1;
}

sub get_provider_specific_dcv_constraints {
    my ( $args, $result ) = @_;

    my $provider = $args->get_length_required('provider');
    my $perl_ns  = Cpanel::Market::get_and_load_module_for_provider($provider);

    $result->data(
        {
            dcv_file_allowed_characters     => _can_or_undef( $perl_ns, 'URI_DCV_ALLOWED_CHARACTERS' ),
            dcv_file_random_character_count => _can_or_undef( $perl_ns, 'URI_DCV_RANDOM_CHARACTER_COUNT' ),
            dcv_file_extension              => _can_or_undef( $perl_ns, 'EXTENSION' ),
            dcv_file_relative_path          => _can_or_undef( $perl_ns, 'URI_DCV_RELATIVE_PATH' ),
            dcv_user_agent_string           => _can_or_undef( $perl_ns, 'DCV_USER_AGENT' ),
            dcv_max_redirects               => _can_or_undef( $perl_ns, 'HTTP_DCV_MAX_REDIRECTS' ),
        }
    );

    return 1;
}

sub _can_or_undef {
    my ( $provider, $function ) = @_;

    if ( my $func = $provider->can($function) ) {
        return scalar $func->();
    }

    return undef;
}

sub get_all_products {
    my ( $args, $result ) = @_;

    my %data = do {
        $SIG{'__DIE__'} = 'DEFAULT';
        local $SIG{'__WARN__'} = sub { $result->raw_message(shift) };
        Cpanel::Market::get_adjusted_market_providers_products();
    };

    my @flattened_data;
    for my $provider ( keys %data ) {
        for my $item ( @{ $data{$provider} } ) {
            $item->{provider_name}         = $provider;
            $item->{provider_display_name} = Cpanel::Market::get_provider_display_name($provider);
            push @flattened_data, $item;
        }
    }

    $result->data( \@flattened_data );

    return 1;
}

#A generic function to allow purchases of non-SSL items.
#This handles one provider at a time; if the user has chosen items from
#multiple providers, then the UI has to process those as separate orders.
#(There is no concept here of a single order with multiple providers.)
#
#Inputs (all required) are:
#   - provider
#   - access_token
#   - url_after_checkout
#   - 1 or more “item” arguments (e.g., “item”, “item-1”, …)
#       Each “item” is a JSON hash of:
#       - product_id
#       - … and whatever else the provider requires for that item
#
sub create_shopping_cart {
    my ( $args, $result ) = @_;

    my @items = _get_required_multiple_json( $args, 'item' );

    my %catalog = Cpanel::Market::get_adjusted_market_providers_products();

    my $provider          = $args->get_length_required('provider');
    my $provider_items_ar = $catalog{$provider};

    for my $item (@items) {
        my $item_is_ok;
        if ($provider_items_ar) {
          PRODUCT_ITEM:
            for my $pitem (@$provider_items_ar) {
                next if $pitem->{'product_id'} ne $item->{'product_id'};
                next if !$pitem->{'enabled'};
                $item_is_ok = 1;
                last PRODUCT_ITEM;
            }
        }

        if ( !$item_is_ok ) {
            die Cpanel::Exception->create( 'There is no available product with [asis,ID] “[_1]” from a provider named “[_2]” ([_3]).', [ $item->{'product_id'}, Cpanel::Market::get_provider_display_name($provider), $provider ] );
        }

        _do_provider( $args, 'validate_request_for_one_item', %$item );
    }

    my ( $order_id, $order_items_ar ) = _do_provider(
        $args,
        'create_shopping_cart',
        access_token       => $args->get_length_required('access_token'),
        url_after_checkout => scalar( $args->get_length_required('url_after_checkout') ),
        items              => \@items,
    );

    $result->data(
        {
            order_id     => $order_id,
            checkout_url => scalar _do_provider( $args, 'get_checkout_url', $order_id ),
            order_items  => $order_items_ar,
        },
    );

    return 1;
}

###########################################################################################
###########################################################################################
####                                                                                   ####
####      Begin /frontend/jupiter/store related functions.                       ####
####                                                                                   ####
###########################################################################################
###########################################################################################

=head2 get_build_cart_url

Returns the URL in cPanel that triggers the shopping cart creation. This should be passed into the
login request so that it can redircet back to the page that begins the order process.

This is only applicable if you're using the /frontend/jupiter/store/..... templates for your
product purchase workflow.

Argument:

env - Hash - Pass in a copy of the environment hash.
The specific fields that are needed are: HTTPS, HTTP_HOST, SERVER_PORT, cp_security_token.

domain - String - The domain for which the purchase process is being started.

=cut

sub get_build_cart_url {
    my ( $args, $result ) = @_;

    my $env          = $args->get('env') // \%ENV;
    my $product_name = $args->get('product_name') || die("You must specify a product name\n");
    my $domain       = $args->get('domain');

    my $session_data = {
        current => {
            cpst         => $env->{cp_security_token},
            product_name => $product_name,
            domain       => $domain,
        },
    };

    Cpanel::Market::Provider::cPStore::Utils::save_session_data($session_data);

    my $qs = Cpanel::HTTP::QueryString::make_query_string(
        product_name => $product_name,
        $domain ? ( domain => $domain ) : (),
    );
    my $url = _build_url( $env, "/frontend/jupiter/store/purchase_product_build_cart.html?$qs" );

    $result->data(
        {
            url => $url,
        }
    );

    return 1;
}

=head2 _build_url (Private helper function)

Given C<env> (hash ref) and C<path> (string), builds a full cPanel URL (including security token) for
a redirect to a page within cPanel. This is needed for redirects back in from outside.

=cut

sub _build_url {
    my ( $env, $path ) = @_;

    my $url_not_available = grep { !$env->{$_} } qw(HTTP_HOST SERVER_PORT cp_security_token);

    if ($url_not_available) {
        die 'The URL could not be built because the server information was not available from the environment.';
    }

    $path =~ s{^/}{};    # added by sprintf below

    return sprintf(
        '%s://%s:%s%s/%s',
        $env->{HTTPS} eq 'on' ? 'https' : 'http',
        $env->{HTTP_HOST},
        $env->{SERVER_PORT},
        $env->{cp_security_token},
        $path,
    );
}

=head2 create_shopping_cart_non_ssl

Given C<access_token>, C<product_name>, and C<url_after_checkout>, sets up the order for the
product. The access token is the one you obtained during the initial account.cpanel.net login.

This function is for use with products other than SSL certificates.

TODO: Make the original create_shopping_cart function work with non-SSL products.

=cut

sub create_shopping_cart_non_ssl {
    my ( $args, $result ) = @_;

    my $access_token = $args->get('access_token');
    my $product_name = $args->get('product_name');
    my $domain       = $args->get('domain');               # optional
    my $redirect_url = $args->get('url_after_checkout');
    my $env          = $args->get('env') // \%ENV;

    # This URL only needs to be known here so that it can be passed in to validate_login_token.
    # The token validation API requires the URL to match the one that was originally supplied
    # when the token was generated.
    my $url_result = Cpanel::API::execute_or_die(
        'Market',
        'get_build_cart_url',
        {
            env          => $env,
            product_name => $product_name,
            domain       => $domain,
        },
    );
    my $this_url = $url_result->data->{url};

    my $response = Cpanel::cPStore::validate_login_token( $access_token, $this_url );

    my $token = $response->{token};

    my $session_data = Cpanel::Market::Provider::cPStore::Utils::get_session_data();
    $session_data->{current}{token} = $token;
    Cpanel::Market::Provider::cPStore::Utils::save_session_data($session_data);

    my $product_info_result = Cpanel::API::execute_or_die(
        'Market',
        'get_product_info',
        {
            product_name => $product_name,
            env          => $env,
        },
    );
    my $product_id = $product_info_result->data->{product_id};

    my ( $order_id, $order_items_ref ) = Cpanel::Market::Provider::cPStore::create_shopping_cart(
        access_token       => $token,
        url_after_checkout => $redirect_url,
        items              => [
            {
                'product_id' => $product_id,
                'ips'        => [ _mainserverip() ],
                $domain ? ( domain => $domain ) : (),
            }
        ],
    );

    my $checkout_url = Cpanel::cPStore::CHECKOUT_URI_WHM($order_id);

    $result->data(
        {
            order_id        => $order_id,
            order_items_ref => $order_items_ref,
            checkout_url    => $checkout_url,
        }
    );

    return 1;
}

=head2 _mainserverip()

Determines public facing IP address and stores it as a class field if not
already set; return main server IP address (String).

=cut

sub _mainserverip {
    return Cpanel::NAT::get_public_ip( Cpanel::DIp::MainIP::getmainserverip() );
}

=head2 get_product_info

Given C<product_name> (string) and C<env> (hash), this looks up the
product id from a file on disk that could be provided by, for example,
a cPAddon or some sort of plugin. The product name used here is the one
passed around in the cPanel query string during the purchase process
and does not necessarily correspond to any of the product names in the
cPanel store.

This is only applicable if you are purchasing a product whose product info
is distributed through a JSON file under /var/cpanel/market/product_info.
This may be helpful if the product is tied to an RPM or some type of plugin,
which would supply this information on install rather than having it built
directly into cPanel & WHM.

=cut

sub get_product_info {
    my ( $args, $result ) = @_;

    my $product_name = $args->get('product_name');
    my $env          = $args->get('env') // \%ENV;

    die "Product name missing or invalid\n" if !$product_name || $product_name =~ /\W/;

    require Cpanel::JSON;
    my $product_info = eval { Cpanel::JSON::LoadFile("/var/cpanel/market/product_info/$product_name") };
    if ( my $exception = $@ ) {
        Cpanel::Logger->new->warn($exception);
        die "The product info file for $product_name could not be loaded\n";    # Intentionally hiding error message to avoid huge dump of text
    }

    my $product_id    = $product_info->{product_id}    || die "Could not find a product id for $product_name\n";
    my $redirect_path = $product_info->{redirect_path} || die "Could not find a redirect_path for $product_name\n";

    my $domain;
    my $session_data = Cpanel::Market::Provider::cPStore::Utils::get_session_data()->{current};
    if (   $session_data->{cpst} eq $env->{cp_security_token}
        && $session_data->{product_name} eq $product_name ) {
        $domain = $session_data->{domain};
    }

    my $redirect_url_failure = my $redirect_url_success = _build_url( $env, $redirect_path );

    if ($domain) {

        # Assumption: Whichever redirect URL is provided in the product info will be able to
        #             handle the 'domain' query string parameter.
        my $qs_success = Cpanel::HTTP::QueryString::make_query_string( { domain => $domain, successful_purchase => 1 } );
        $redirect_url_success .= ( $redirect_url_success =~ /\?/ ? "&$qs_success" : "?$qs_success" );

        my $qs_failure = Cpanel::HTTP::QueryString::make_query_string( { domain => $domain, successful_purchase => 0 } );
        $redirect_url_failure .= ( $redirect_url_failure =~ /\?/ ? "&$qs_failure" : "?$qs_failure" );
    }

    $result->data(
        {
            product_id           => $product_id,
            redirect_path        => $redirect_path,
            redirect_url_success => $redirect_url_success,
            redirect_url_failure => $redirect_url_failure,
        }
    );

    return 1;
}

=head2 get_completion_url

Given C<env> which needs to have at least HTTP_HOST, SERVER_PORT, and cp_security_token, build
a full URL to the completion path. The caller must also specify C<product_name>.

=cut

sub get_completion_url {
    my ( $args, $result ) = @_;

    my $env          = $args->get('env') // \%ENV;
    my $product_name = $args->get('product_name') || die("You must specify a product name\n");

    my $path           = '/frontend/jupiter/store/purchase_' . $product_name . '_completion.html';
    my $completion_url = _build_url( $env, $path );
    $result->data(
        {
            completion_url => $completion_url,
        },
    );
    return 1;
}

sub get_license_info {
    my ($args) = @_;

    my $domain = $args->get('domain');

    my $key = Cpanel::Market::Provider::cPStore::Utils::get_license_details($domain);

    my $session_data = Cpanel::Market::Provider::cPStore::Utils::get_session_data();
    $session_data->{license}{$domain} = $key;
    Cpanel::Market::Provider::cPStore::Utils::save_session_data($session_data);

    return;
}

###########################################################################################
###########################################################################################
####                                                                                   ####
####      Everything below this line is specific to SSL certificate purchases.         ####
####                                                                                   ####
###########################################################################################
###########################################################################################

#inputs: provider, order_item_id, status
#
# Sets the status of pending queue item
# to provided value.
#
# As of now the only acceptable value is “confirmed”.
# It is anticipated that other values may be needed in the future.
#
sub set_status_of_pending_queue_items {
    my ( $args, $result ) = @_;

    my $order_item_status = $args->get_length_required('status');

    my @accepted_states = qw(
      confirmed
    );

    if ( $order_item_status ne 'confirmed' ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The “[_1]” parameter must be one of the following: [list_and_quoted,_2]', [ 'status', \@accepted_states ] );

    }

    my $provider       = $args->get_length_required('provider');
    my @order_item_ids = $args->get_length_required_multiple('order_item_id');

    my $poll_db     = Cpanel::SSL::PendingQueue->new();
    my @queue_items = $poll_db->read();

    my %passed_in_oiid_matches;
    @passed_in_oiid_matches{@order_item_ids} = ();

    for my $item (@queue_items) {
        next if $item->provider() ne $provider;
        my $oiid = $item->order_item_id();

        if ( grep { $_ eq $oiid } @order_item_ids ) {
            delete $passed_in_oiid_matches{$oiid};
            $item->status($order_item_status);
            $poll_db->update_item($item);
        }
    }

    if (%passed_in_oiid_matches) {
        my @leftovers = keys %passed_in_oiid_matches;
        $result->data(
            {
                error_type     => 'EntryDoesNotExist',
                order_item_ids => \@leftovers,
            },
        );

        die Cpanel::Exception::create( 'EntryDoesNotExist', 'The order item [numerate,_1,ID,IDs] [list_and_quoted,_2] [numerate,_1,does,do] not match any entries in the pending queue.', [ 0 + @leftovers, \@leftovers ] );
    }

    $poll_db->finish();

    return 1;
}

sub _pending_item_to_return {
    my ($item) = @_;

    my $r = $item->to_hashref();
    $r->{'domains'} = [ $item->domains() ];

    my $provider_ns = Cpanel::Market::get_and_load_module_for_provider( $item->provider() );

    $r->{'checkout_url'} = $provider_ns->can('get_checkout_url')->( $item->order_id() );

    $r->{'support_uri'} = $provider_ns->can('get_support_uri_for_order_item')->(
        ( map { $_ => $item->$_() } qw( order_id  order_item_id ) ),
    );

    #The CSR parse is a very proprietary, “unpolished” data structure.
    #Unless people really want it, let’s save ourselves the documentation
    #and maintenance overhead.
    delete $r->{'csr_parse'};

    return $r;
}

sub get_pending_ssl_certificates {
    my ( $args, $result ) = @_;

    my @data = map { _pending_item_to_return($_); } Cpanel::SSL::PendingQueue->read();

    $result->data( \@data );

    return 1;
}

#NOTE: The “access_token” is obtained via validate_login_token().
#
#See Cpanel::Market::SSL for documentation of this function.
#The only difference is that, instead of “certificates”, this accepts
#multiple “certificate” arguments, each of which is a JSON serialization
#of the relevant data structure.
sub request_ssl_certificates {
    my ( $args, $result ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::Market::SSL');

    my @certs = _get_required_multiple_json( $args, 'certificate' );

    local $SIG{'__WARN__'} = sub {
        my $msg = shift;
        $result->raw_message($msg);
    };

    my $data = Cpanel::Market::SSL::request_ssl_certificates(
        provider           => $args->get_length_required('provider'),
        access_token       => $args->get_length_required('access_token'),
        url_after_checkout => scalar( $args->get('url_after_checkout') ),
        certificates       => \@certs,
    );

    $result->data($data);

    return 1;
}

sub set_url_after_checkout {
    my ( $args, $result ) = @_;

    Cpanel::Security::Authz::verify_user_has_feature( $Cpanel::user, 'market' );
    Cpanel::Security::Authz::verify_user_has_feature( $Cpanel::user, 'tls_wizard' );

    my $access_token       = $args->get_length_required('access_token');
    my $order_id           = $args->get_length_required('order_id');
    my $url_after_checkout = $args->get_length_required('url_after_checkout');

    try {
        $result->data( _do_provider( $args, 'set_url_after_checkout', 'order_id' => $order_id, 'access_token' => $access_token, 'url_after_checkout' => $url_after_checkout ) );
    }
    catch {
        if ( try { $_->isa('Cpanel::Exception::Market') } ) {
            $result->data( { error_type => ( ref =~ s<.+::><>r ) } );
        }

        local $@ = $_;
        die;
    };

    return 1;
}

sub get_ssl_certificate_if_available {
    my ( $args, $result ) = @_;

    my $oiid = $args->get_length_required('order_item_id');

    $result->data( _do_provider( $args, 'get_certificate_if_available', $oiid ) );

    return 1;
}

sub get_certificate_status_details {
    my ( $args, $result ) = @_;

    my $oiid = $args->get_length_required('order_item_id');

    $result->data( _do_provider( $args, 'get_certificate_status_details', $oiid ) );

    return 1;
}

sub _get_required_multiple_json {
    my ( $args, $varname ) = @_;

    my @things = $args->get_length_required_multiple($varname);

    if ( !@things ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => $varname ] );
    }

    return map { Cpanel::JSON::Load($_) } @things;
}

1;
