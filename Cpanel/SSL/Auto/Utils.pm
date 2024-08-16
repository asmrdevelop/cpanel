package Cpanel::SSL::Auto::Utils;

# cpanel - Cpanel/SSL/Auto/Utils.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Utils - common utilities for AutoSSL modules

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Context            ();
use Cpanel::Exception          ();
use Cpanel::LoadModule::Custom ();
use Cpanel::LoadModule::Name   ();

#Accessed from tests
our $_PROVIDER_MODULE_NAMESPACE_ROOT;
*_PROVIDER_MODULE_NAMESPACE_ROOT = \( ( __PACKAGE__ =~ s<::[^:]+\z><>r ) . '::Provider' );

=head2 validate_property_name( NAME )

Throws if the given NAME is invalid.

=cut

sub validate_property_name {
    my ($key) = @_;

    if ( !length $key ) {
        die Cpanel::Exception::create( 'Empty', 'The key cannot be empty.' );
    }

    if ( ref($key) || $key !~ tr<0-9><>c ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'The key can only be a string, not “[_1]”.', [$key] );
    }

    return;
}

=head2 get_provider_module_names()

Returns a list of module names. These are not meant for display to a user
but are what this module expects to identify a given provider module. No
order is defined for the returned list.

=cut

sub get_provider_module_names {
    Cpanel::Context::must_be_list();

    #uniq
    my %modules;
    @modules{ _get_stock_provider_module_names() } = ();
    @modules{ Cpanel::LoadModule::Custom::list_modules_for_namespace($_PROVIDER_MODULE_NAMESPACE_ROOT) } = ();

    return keys %modules;
}

=head2 provider_exists_or_die( MODULE_NAME )

=cut

sub provider_exists_or_die {
    my ($provider) = @_;

    if ( !grep { $_ eq $provider } get_provider_module_names() ) {
        die Cpanel::Exception->create( 'This system does not have an [asis,AutoSSL] provider whose module name is “[_1]”.', [$provider] );
    }

    return;
}

=head2 get_provider_namespace( MODULE_NAME )

=cut

sub get_provider_namespace {
    my ($provider) = @_;

    return "${_PROVIDER_MODULE_NAMESPACE_ROOT}::$provider";
}

#mocked in tests
sub _get_stock_provider_module_names {
    my $stock_modules_path = __FILE__;
    $stock_modules_path =~ s<[^/]+\z><> or die "Failed to alter path: “$stock_modules_path”!";
    $stock_modules_path .= 'Provider';

    return Cpanel::LoadModule::Name::get_module_names_from_directory($stock_modules_path);
}

1;
