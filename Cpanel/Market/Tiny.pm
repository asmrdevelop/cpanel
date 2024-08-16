package Cpanel::Market::Tiny;

# cpanel - Cpanel/Market/Tiny.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::FileUtils::Write   ();
use Cpanel::Autodie            ();
use Cpanel::LoadModule         ();
use Cpanel::Context            ();
use Cpanel::LoadModule::Custom ();

our $_PROVIDER_MODULE_NAMESPACE_ROOT = "Cpanel::Market::Provider";

our $CPMARKET_CONFIG_DIR = '/var/cpanel/market';

my $CPMARKET_CONFIG_DIR_PERMS = 0711;    # User has to be able to traverse

my $_CPMARKET_HAS_ENABLED_PROVIDERS_FILE       = 'enabled_providers_count';
my $_CPMARKET_HAS_ENABLED_PROVIDERS_FILE_PERMS = 0644;                        # User has to be able to read

#Returns the # of enabled providers,
#as stored in the “enabled_providers_count” file.
#
#(Returns undef if that file doesn’t exist.)
#
sub get_enabled_providers_count {

    # This only dies if it has trouble checking for existence, not if it doesn't exist
    Cpanel::Autodie::exists("$CPMARKET_CONFIG_DIR/$_CPMARKET_HAS_ENABLED_PROVIDERS_FILE");
    return scalar( ( stat _ )[7] );
}

sub set_enabled_providers_count {
    my ($count) = @_;

    Cpanel::FileUtils::Write::overwrite(
        "$CPMARKET_CONFIG_DIR/$_CPMARKET_HAS_ENABLED_PROVIDERS_FILE",
        "!" x $count,
        $_CPMARKET_HAS_ENABLED_PROVIDERS_FILE_PERMS,
    );

    return 1;
}

sub create_market_directory_if_missing {
    return if $> != 0;

    Cpanel::LoadModule::load_perl_module('Cpanel::Mkdir');

    Cpanel::Mkdir::ensure_directory_existence_and_mode(
        $CPMARKET_CONFIG_DIR,
        $CPMARKET_CONFIG_DIR_PERMS,
    );

    return;
}

sub get_provider_names {
    Cpanel::Context::must_be_list();

    my %modules;
    @modules{ Cpanel::LoadModule::Custom::list_modules_for_namespace($_PROVIDER_MODULE_NAMESPACE_ROOT) } = ();

    #NOTE: There was logic to crawl all through @INC here,
    #but that seems superfluous.

    return ( 'cPStore', keys %modules );
}

1;
