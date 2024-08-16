package Cpanel::Config::ConfigObj::Driver::Market::META;

# cpanel - Cpanel/Config/ConfigObj/Driver/Market/META.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw(Cpanel::Config::ConfigObj::Interface::Config::Version::v1);

our $VERSION = '1.1';

use Cpanel::License    ();
use Cpanel::LoadModule ();
use Try::Tiny;

=head1 NAME

Cpanel::Config::ConfigObj::Driver::Market::META

=head1 DESCRIPTION

Feature Showcase META driver for Market

=cut

=head1 SYNOPSIS

Boilerplate subroutines for the feature showcase.

=cut

=head1 Subroutines

=head2 meta_version

The default version for feature showcase drivers

=cut

sub meta_version {
    return 1;
}

=head2 get_driver_name

The name of the cpanel ssl wizard page driver

=cut

# Avoids having to deal with locale information
# when all we care about is the driver name.
sub get_driver_name {
    return 'market';
}

=head2 content

Boilerplate content for a META module

=cut

sub content {
    my ($locale_handle) = @_;

    my $content = {
        'vendor' => 'cPanel, Inc.',
        'url'    => 'https://go.cpanel.net/featureshowcasemarket',
        'name'   => {
            'short'  => 'The SSL/TLS Wizard in cPanel.',
            'driver' => get_driver_name(),
        },
        'since'    => '11.64',
        'abstract' => 'The SSL/TLS Wizard in cPanel provides users with the ability to purchase SSL/TLS certificates.' . ' '
          . 'This feature requires that you enable at least one market provider. There are currently no market providers enabled, the system will enable the “cPStore” market provider to activate this functionality.' . ' '
          . 'If you plan to use a custom market provider you should not use this interface to enable this functionality.',
        'version' => $VERSION,
    };

    if ($locale_handle) {
        $content->{'name'}->{'short'} = $locale_handle->maketext('The [asis,SSL/TLS] Wizard in cPanel.');
        $content->{'abstract'} =
            $locale_handle->maketext('The [asis,SSL/TLS] Wizard in cPanel provides users with the ability to purchase [asis,SSL/TLS] certificates.') . ' '
          . $locale_handle->maketext( 'This feature requires that you enable at least one market provider. There are currently no market providers enabled, the system will enable the “[_1]” market provider to activate this functionality.', 'cPStore' ) . ' '
          . $locale_handle->maketext( '[output,strong,If you plan to use a] [output,url,_1,custom market provider,target,_blank] [output,strong,you should not use this interface to enable this functionality].',                              'https://go.cpanel.net/custommarketproviderwizard' );
    }

    $content->{'name'}->{'long'} = $content->{'name'}->{'short'};

    return $content;
}

=head2 showcase

Boilerplate to display in the feature showcase

=cut

sub can_be_enabled {
    Cpanel::LoadModule::load_perl_module('Cpanel::Market::Tiny');

    # If any provider is enabled we never show the feature showcase item as we don't
    # want to interfere with their market provider.
    return 0 if Cpanel::Market::Tiny::get_enabled_providers_count();

    return 0 if $< != 0;

    return 0 if !Cpanel::License::is_licensed();

    require Cpanel::Market::Provider::cPStore;
    require Cpanel::cPStore;

    local $Cpanel::cPStore::TIMEOUT = 5;    # do not block the UI if the store is not reachable
    my @products;
    try {
        @products = Cpanel::Market::Provider::cPStore::get_products_list();
    }
    catch {
        Cpanel::LoadModule::load_perl_module('Cpanel::Debug');
        Cpanel::Debug::log_warn("Failed to fetch cPStore products list: $_");
    };

    # If the cPStore market provider is disabled by the partner then we never show the feature showcase item
    return 0 if !@products;

    return 1;
}

sub showcase {
    return undef if !can_be_enabled();

    #  If check() is false we should not get here because
    #  they already have a market provider enabled or the
    #  partner has disabled the cPStore market provider
    return { 'is_spotlight_feature' => 0 };
}

=head2 auto_enable

Returns whether or not this feature is auto-enabled.

=cut

sub auto_enable {
    return can_be_enabled();
}

1;
