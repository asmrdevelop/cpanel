package Cpanel::Market;

# cpanel - Cpanel/Market.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Market - Loader for cPanel Market “provider” modules

=head1 SYNOPSIS

    use Cpanel::Market ();

    my $perl_ns;

    $perl_ns = Cpanel::Market::get_and_load_module_for_provider('cPStore');

    #Custom module loads the same way as a cPanel-provided one.
    $perl_ns = Cpanel::Market::get_and_load_module_for_provider('BobsStuff');

    #----------------------------------------------------------------------
    my @providers = Cpanel::Market::Tiny::get_provider_names();
    my @enabled_providers = Cpanel::Market::get_enabled_provider_names();

    #----------------------------------------------------------------------
    # Admin functions:

    Cpanel::Market::enable_provider('ProviderName');
    Cpanel::Market::disable_provider('ProviderName');

=head1 DESCRIPTION

This module will validate modules before it returns the name of the module.
You can subsequently execute functions on the module by doing:

    $perl_ns->can($function_name)->(@args)

=cut

use strict;
use warnings;

use Cpanel::Autodie                       ();
use Cpanel::Mkdir                         ();
use Cpanel::Context                       ();
use Cpanel::Exception                     ();
use Cpanel::LoadModule::Custom            ();
use Cpanel::LoadModule::Utils             ();
use Cpanel::LoadModule                    ();
use Cpanel::Transaction::File::JSONReader ();
use Cpanel::Validate::AuthProvider        ();
use Cpanel::FileUtils::TouchFile          ();
use Cpanel::Market::Tiny                  ();
use Try::Tiny;

our $_CPMARKET_CONFIG_FILE       = 'cpmarket_config.json';
our $_CPMARKET_CONFIG_FILE_PERMS = 0644;                     # User has to be able to read

our $_CPMARKET_ADJUSTMENT_CONFIG_FILE = 'product_adjustments.json';

our $_CPSTORE_IN_SYNC_FLAG_FILE = '/var/cpanel/market/cpstore_is_in_sync';

our $_CPMARKET_COMMISSION_CONFIG_DIR = '/var/cpanel/market/commission';
our $_CPMARKET_COMMISSION_DIR_PERMS  = 0711;
our $_CPMARKET_COMMISSION_FILE_PERMS = 0640;

#accessed from tests
our @_REQUIRED_METHODS = qw(
  create_shopping_cart
  get_checkout_url
  get_support_uri_for_order_item
  get_login_url
  get_products_list
  set_url_after_checkout
  validate_login_token
  validate_request_for_one_item
);

#These are SSL-specific:
#  prepare_system_for_request_validation
#  undo_request_validation_preparation

*get_provider_names = *Cpanel::Market::Tiny::get_provider_names;

sub get_provider_display_name {
    my ($provider) = @_;

    my $ns = get_and_load_module_for_provider($provider);

    return $ns->can('_DISPLAY_NAME') ? $ns->_DISPLAY_NAME() : $provider;
}

sub get_enabled_provider_names {
    Cpanel::Context::must_be_list();

    my $config_file = _get_market_config_file();

    my $conf;

    if ( Cpanel::Autodie::exists($config_file) ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $config_file );
        $conf = $reader_transaction->get_data();
    }

    return ( 'HASH' eq ref $conf ) ? grep { $conf->{$_}{'enabled'} } keys %$conf : ();
}

sub get_and_load_module_for_provider {
    my ($provider) = @_;

    my $module = _get_provider_ns($provider);

    # Checking to see if the module is complete can be expensive
    # so lets only do it once per load
    if ( !Cpanel::LoadModule::Utils::module_is_loaded($module) ) {

        #This will load a custom module if one is available,
        #then fall back to cPanel-provided if not.
        Cpanel::LoadModule::Custom::load_perl_module($module);

        _verify_that_module_is_complete($module);
    }

    return $module;
}

sub enable_provider {
    my ($provider) = @_;

    return _set_provider_enabled_state( $provider, 1 );
}

sub disable_provider {
    my ($provider) = @_;

    return _set_provider_enabled_state( $provider, 0 );
}

sub _set_provider_enabled_state {
    my ( $provider, $enabled ) = @_;

    # It may be time to move this to another namespace? Or make a common namespace for things like this
    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    my $transaction = _get_market_config_transaction();

    my $number_of_enabled_providers = 0;

    #Ensure that this is a real provider module before we enable it.
    get_and_load_module_for_provider($provider) if $enabled;

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($providers) = @_;

            $providers->{$provider}{'enabled'} = $enabled;

            $number_of_enabled_providers = scalar grep { $providers->{$provider}{'enabled'} } keys %{$providers};

            return 1;
        }
    );

    Cpanel::Market::Tiny::set_enabled_providers_count($number_of_enabled_providers);

    Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );

    return 1;
}

sub get_market_product_adjustments {
    my $config_file = _get_product_adjustment_config_file();

    my $conf;

    if ( Cpanel::Autodie::exists($config_file) ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $config_file );
        $conf = $reader_transaction->get_data();
    }

    return ( 'HASH' eq ref $conf ) ? $conf : {};
}

#Returns a list of key/value pairs:
#   ProviderModule => [
#       {
#           product_id => ..,
#           product_group => ..,
#           display_name => ..,
#           price => ..,
#           enabled => ..,
#           recommended => ..,
#       },
#       ...,
#   ],
#   ...,
#
#This will warn() on a failure to execute a provider’s get_product_list()
#rather than blow up completely.
sub get_adjusted_market_providers_products {
    Cpanel::Context::must_be_list();

    my $adjustments = get_market_product_adjustments();

    return _get_adjusted_products($adjustments);
}

# Currently, assume root.
sub get_market_commission_config {
    my $config_file = _get_market_commission_config_file('root');

    my $conf;

    if ( Cpanel::Autodie::exists($config_file) ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $config_file );
        $conf = $reader_transaction->get_data();
    }

    $conf = {} if 'HASH' ne ref $conf;

    for my $provider_name ( get_enabled_provider_names() ) {
        if ( !exists $conf->{$provider_name} || !exists $conf->{$provider_name}{'commission_id'} ) {
            $conf->{$provider_name}{'commission_id'}{'local'} = undef;
        }

        my $provider_namespace = get_and_load_module_for_provider($provider_name);
        if ( my $get_commission_id_cr = $provider_namespace->can('get_commission_id') ) {
            $conf->{$provider_name}{'commission_id'}{'remote'} = $get_commission_id_cr->();
        }
    }

    return $conf;
}

sub get_market_provider_local_commission_id {
    my ($provider) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    my $config_file = _get_market_commission_config_file('root');
    my $conf;

    if ( Cpanel::Autodie::exists($config_file) ) {
        my $reader_transaction = Cpanel::Transaction::File::JSONReader->new( path => $config_file );
        $conf = $reader_transaction->get_data();
    }
    if ($conf) {
        return $conf->{$provider}{'commission_id'}{'local'};
    }
    return undef;
}

# Currently, assume root.
sub set_market_provider_commission_id {
    my ( $provider, $commission_id ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'commission_id' ] ) if !length $commission_id;

    my $provider_namespace = get_and_load_module_for_provider($provider);
    if ( my $set_cr = $provider_namespace->can('set_commission_id') ) {
        $set_cr->( 'commission_id' => $commission_id );
    }

    my $transaction = _get_market_commission_config_transaction('root');
    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($config) = @_;

            $config->{$provider}{'commission_id'}{'local'} = $commission_id;

            return 1;
        }
    );

    return 1;
}

sub enable_market_product {
    my ( $provider, $product_id ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    _validate_product_id_against_product_list( $provider, $product_id );

    my $transaction = _get_product_adjustment_config_transaction();

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($adjustments) = @_;

            return 0 if !$adjustments->{$provider};
            return 0 if !$adjustments->{$provider}{$product_id};

            # The default of enabled is 1, so just delete it to keep the db cleaner.
            _clean_up_adjustments_hashref( $provider, $product_id, 'enabled', $adjustments );

            return 1;
        }
    );

    return 1;
}

sub disable_market_product {
    my ( $provider, $product_id ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    _validate_product_id_against_product_list( $provider, $product_id );

    my $transaction = _get_product_adjustment_config_transaction();

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($adjustments) = @_;

            $adjustments->{$provider}{$product_id}{'enabled'} = 0;

            return 1;
        }
    );

    return 1;
}

sub get_cpstore_is_in_sync_flag {
    return -e $_CPSTORE_IN_SYNC_FLAG_FILE ? 1 : 0;
}

sub set_cpstore_is_in_sync_flag {
    my ($in_sync) = @_;

    Cpanel::Market::Tiny::create_market_directory_if_missing();

    if ($in_sync) {
        return Cpanel::FileUtils::TouchFile::touchfile($_CPSTORE_IN_SYNC_FLAG_FILE);
    }
    return unlink($_CPSTORE_IN_SYNC_FLAG_FILE);
}

sub sync_local_config_to_cpstore {
    return if get_cpstore_is_in_sync_flag();

    # Now need to sync to the store if not enabled
    my $provider = 'cPStore';
    return if !grep { $_ eq $provider } get_enabled_provider_names();

    my $sync_ok = 1;

    foreach my $call (qw(sync_local_commision_id_to_remote sync_local_products_to_remote)) {
        try {
            __PACKAGE__->can($call)->($provider);
        }
        catch {
            local $@ = $_;
            warn;
            $sync_ok = 0;
        };
    }

    set_cpstore_is_in_sync_flag(1) if $sync_ok;

    return $sync_ok;
}

sub sync_local_products_to_remote {
    my ($provider) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    my $provider_namespace = get_and_load_module_for_provider($provider);
    my $set_cr             = $provider_namespace->can('set_attribute_value');
    my @exceptions;

    if ( my $provider_product_attributes = get_market_provider_product_attributes($provider) ) {
        foreach my $product_id ( sort keys %{$provider_product_attributes} ) {
            foreach my $attribute ( sort keys %{ $provider_product_attributes->{$product_id}{'attributes'} } ) {
                my $value = $provider_product_attributes->{$product_id}{'attributes'}{$attribute};
                try {
                    $set_cr->( 'product_id' => $product_id, 'key' => $attribute, 'value' => $value );
                }
                catch {
                    push @exceptions, $_;
                };
            }
        }
    }

    if (@exceptions) {
        die Cpanel::Exception::create( 'Collection', [ exceptions => \@exceptions ] );
    }

    return 1;
}

sub sync_local_commision_id_to_remote {
    my ($provider) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);
    if ( my $commision_id = get_market_provider_local_commission_id($provider) ) {
        return set_market_provider_commission_id( $provider, $commision_id );
    }
    return 0;
}

sub get_market_provider_product_attributes {
    my ($provider) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    my $config_file = _get_product_adjustment_config_file();
    if ( Cpanel::Autodie::exists($config_file) ) {
        my $transaction = Cpanel::Transaction::File::JSONReader->new( path => $config_file );
        my $data        = $transaction->get_data();
        return $data->{$provider};
    }
    return undef;
}

# NOTE: The attributes 'recommended' and 'enabled' have their own setters, please use those for now.
#       Those attributes are currently injected by us, so we handle them a bit differently behind the scenes.
sub adjust_market_product_attribute {
    my ( $provider, $product_id, $attribute, $value ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    _validate_product_id_against_product_list( $provider, $product_id );

    die Cpanel::Exception::create( 'MissingParameter', [ name => 'attribute' ] ) if !length $attribute;

    my $transaction = _get_product_adjustment_config_transaction();

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($adjustments) = @_;

            if ( length $value ) {
                $adjustments->{$provider}{$product_id}{'attributes'}{$attribute} = $value;
            }
            else {
                delete $adjustments->{$provider}{$product_id}{'attributes'}{$attribute};
                if ( !keys %{ $adjustments->{$provider}{$product_id}{'attributes'} } ) {
                    _clean_up_adjustments_hashref( $provider, $product_id, 'attributes', $adjustments );
                }
            }

            return 1;
        }
    );

    return 1;
}

sub get_market_providers_product_metadata {
    my @providers = get_enabled_provider_names();

    my $product_metadata = {};
    for my $provider (@providers) {
        my $metadata = get_market_provider_product_metadata($provider);
        $product_metadata->{$provider} = $metadata if $metadata && keys %$metadata;
    }

    return $product_metadata;
}

sub get_market_provider_product_metadata {
    my ($provider) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    my $provider_namespace = get_and_load_module_for_provider($provider);
    my $metadata;

    if ( my $get_metadata_func = $provider_namespace->can('get_product_metadata') ) {
        $metadata = $get_metadata_func->();
    }

    # Providers may not implement this correctly or at all.. lets clean it up since we need to augment it.
    $metadata ||= {};

    my $products = _get_products_from_provider($provider);

    for my $product (@$products) {

        #“read_only” defaults to 1; the provider module has to
        #DISABLE this flag specifically for an attribute in order
        #to make that attribute editable.
        for my $attribute ( keys %$product ) {
            $metadata->{ $product->{'product_id'} }{'attributes'}{$attribute}{'read_only'} //= 1;
        }

        for my $attribute (qw( enabled recommended )) {
            $metadata->{ $product->{'product_id'} }{'attributes'}{$attribute}{'read_only'} //= 0;
        }
    }

    return $metadata;
}

#This will warn() on a failure to execute a provider’s get_product_list()
#rather than blow up completely.
sub enable_market_product_recommendation {
    my ( $provider, $product_id ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    _validate_product_id_against_product_list( $provider, $product_id );

    my $transaction = _get_product_adjustment_config_transaction();

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($adjustments) = @_;

            my %all_products = _get_adjusted_products($adjustments);

            # We currently (Feb 2016, v56) only allow one product to be recommended per product group.
            # So, we need to de-recommend products in the same product group..
            my ($product_item) = grep { $_->{'product_id'} eq $product_id } @{ $all_products{$provider} };
            my $product_group = $product_item->{'product_group'};

            for my $search_provider ( keys %all_products ) {
                next if !$adjustments->{$search_provider};

                for my $current_product ( @{ $all_products{$search_provider} } ) {
                    next if !$adjustments->{$search_provider}{ $current_product->{'product_id'} };
                    next if !$current_product->{'recommended'};
                    next if $product_group ne $current_product->{'product_group'};
                    next if $provider eq $search_provider && $current_product->{'product_id'} eq $product_id;

                    die Cpanel::Exception::create( 'EntryAlreadyExists', 'You must remove the recommendation from “[_1]” before you can recommend “[_2]”.', [ $current_product->{'display_name'}, $product_item->{'display_name'} ] );
                }
            }

            $adjustments->{$provider}{$product_id}{'recommended'} = 1;

            return 1;
        }
    );

    return 1;
}

sub disable_market_product_recommendation {
    my ( $provider, $product_id ) = @_;

    Cpanel::Validate::AuthProvider::check_provider_name_or_die($provider);

    _validate_product_id_against_product_list( $provider, $product_id );

    my $transaction = _get_product_adjustment_config_transaction();

    _act_on_hashref_data_from_transaction(
        $transaction,
        sub {
            my ($adjustments) = @_;

            return 0 if !$adjustments->{$provider};
            return 0 if !$adjustments->{$provider}{$product_id};
            return 0 if !$adjustments->{$provider}{$product_id}{'recommended'};

            # The default of recommended is 0, so just delete it to keep the db cleaner.
            _clean_up_adjustments_hashref( $provider, $product_id, 'recommended', $adjustments );

            return 1;
        }
    );

    return 1;
}

# Called when we remove something from the adjustments hash
sub _clean_up_adjustments_hashref {
    my ( $provider, $product_id, $key_to_remove, $adjustments ) = @_;

    delete $adjustments->{$provider}{$product_id}{$key_to_remove};
    if ( !keys %{ $adjustments->{$provider}{$product_id} } ) {
        delete $adjustments->{$provider}{$product_id};

        if ( !keys %{ $adjustments->{$provider} } ) {
            delete $adjustments->{$provider};
        }
    }

    return;
}

sub _get_products_from_provider {
    my ($provider) = @_;

    my $provider_namespace = get_and_load_module_for_provider($provider);
    return [ $provider_namespace->can('get_products_list')->() ];
}

sub _get_adjusted_products {
    my ($adjustments) = @_;

    Cpanel::Context::must_be_list();

    my @providers = get_enabled_provider_names();
    my %products  = ();

    for my $provider (@providers) {
        my $provider_products;
        try {
            $provider_products = _get_products_from_provider($provider);
        }
        catch {
            Cpanel::LoadModule::load_perl_module('Cpanel::Locale');
            warn Cpanel::Locale->get_handle()->maketext( 'The system failed to load the market provider module for “[_1]” because of an error: [_2]', $provider, Cpanel::Exception::get_string($_) );
        };

        next if !$provider_products;

        my @provider_products;
        for my $product (@$provider_products) {

            _adjust_product( $adjustments, $provider, $product );

            push @provider_products, $product;
        }

        $products{$provider} = \@provider_products;
    }

    return %products;
}

sub _validate_product_id_against_product_list {
    my ( $provider, $product_id, $products ) = @_;

    if ( !defined $product_id ) {
        die Cpanel::Exception::create( 'MissingParameter', [ name => 'product_id' ] );
    }

    $products = _get_products_from_provider($provider) if !$products;

    return 1 if grep { $_->{'product_id'} eq $product_id } @$products;

    die Cpanel::Exception::create( 'EntryDoesNotExist', 'A product with [asis,ID] “[_1]” does not exist in the product list for the provider “[_2]”.', [ $product_id, $provider ] );
}

sub _adjust_product {
    my ( $adjustments, $provider, $product ) = @_;

    if ( $adjustments->{$provider} && $adjustments->{$provider}{ $product->{'product_id'} } ) {

        my %adjustment = %{ $adjustments->{$provider}{ $product->{'product_id'} } };

        my $attribute_adjustments = delete $adjustment{'attributes'};

        @{$product}{ keys %adjustment } = values %adjustment;

        if ( $attribute_adjustments && keys %$attribute_adjustments ) {
            @{$product}{ keys %$attribute_adjustments } = values %$attribute_adjustments;
        }
    }

    $product->{'enabled'}     //= 1;
    $product->{'recommended'} //= 0;

    return;
}

sub _act_on_hashref_data_from_transaction {
    my ( $transaction, $data_todo_cr ) = @_;

    my $data = $transaction->get_data();

    $data = {} if ref $data ne 'HASH';

    my $dirty = $data_todo_cr->($data);

    if ($dirty) {
        $transaction->set_data($data);

        $transaction->save_and_close_or_die();
    }
    else {
        $transaction->close_or_die();
    }

    $transaction = undef;

    return $dirty;
}

#overridden in tests
sub _verify_that_module_is_complete {
    my ($module) = @_;

    my @missing = grep { !$module->can($_) } @_REQUIRED_METHODS;

    return if !@missing;

    die Cpanel::Exception->create( 'The module “[_1]” is missing the required [numerate,_2,method,methods] [list_and_quoted,_3].', [ $module, scalar(@missing), \@missing ] );
}

sub _get_provider_ns {
    my ($provider) = @_;

    return "${Cpanel::Market::Tiny::_PROVIDER_MODULE_NAMESPACE_ROOT}::$provider";
}

sub _get_market_config_dir {
    return $Cpanel::Market::Tiny::CPMARKET_CONFIG_DIR;
}

sub _get_market_commission_config_dir {
    return $_CPMARKET_COMMISSION_CONFIG_DIR;
}

sub _get_market_commission_config_file {
    my ($user) = @_;

    return _get_market_commission_config_dir() . "/$user.config";
}

sub _get_market_config_file {
    return _get_market_config_dir() . '/' . $_CPMARKET_CONFIG_FILE;
}

sub _get_product_adjustment_config_file {
    return _get_market_config_dir() . '/' . $_CPMARKET_ADJUSTMENT_CONFIG_FILE;
}

sub _get_product_adjustment_config_transaction {
    Cpanel::Market::Tiny::create_market_directory_if_missing();

    my $config_file = _get_product_adjustment_config_file();
    require Cpanel::Transaction::File::JSON;
    return Cpanel::Transaction::File::JSON->new( path => $config_file, permissions => $_CPMARKET_CONFIG_FILE_PERMS );
}

sub _get_market_commission_config_transaction {
    my ($reseller) = @_;

    _create_market_commission_directory_if_missing();

    my $config_file = _get_market_commission_config_file($reseller);
    require Cpanel::Transaction::File::JSON;
    return Cpanel::Transaction::File::JSON->new(
        path        => $config_file,
        permissions => $_CPMARKET_COMMISSION_FILE_PERMS,
        ownership   => [ 'root', $reseller ],
    );
}

sub _get_market_config_transaction {

    Cpanel::Market::Tiny::create_market_directory_if_missing();

    my $config_file = _get_market_config_file();
    require Cpanel::Transaction::File::JSON;
    return Cpanel::Transaction::File::JSON->new( path => $config_file, permissions => $_CPMARKET_CONFIG_FILE_PERMS );
}

sub _create_market_commission_directory_if_missing {
    return if $> != 0;

    Cpanel::Market::Tiny::create_market_directory_if_missing();

    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        _get_market_commission_config_dir(),
        $_CPMARKET_COMMISSION_DIR_PERMS,
    );

    return;
}

1;
