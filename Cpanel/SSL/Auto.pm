package Cpanel::SSL::Auto;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

=pod

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto - AutoSSL dispatch layer

=head1 SYNOPSIS

    my @info = Cpanel::SSL::Auto::get_all_provider_info();

=head1 DESCRIPTION

This module was originally intended as an “access point” for AutoSSL logic;
in point of fact, it now merely serves as a convenient “utils” module.
(Not to be confused with the actual C<Cpanel::SSL::Auto::Utils> module!)

=cut

use strict;
use warnings;

use Try::Tiny;

use Hash::Merge ();

use Cpanel::Context                 ();
use Cpanel::Exception               ();
use Cpanel::SSL::Auto::Config::Read ();
use Cpanel::SSL::Auto::Loader       ();
use Cpanel::SSL::Auto::Utils        ();

#TODO: De-duplicate some of this logic with Cpanel::Market?

=head1 FUNCTIONS

=head2 get_all_provider_info()

Returns a list of hashes, each of which looks like:

    {
        module_name     =>  #string
        enabled         =>  #0 or 1
        display_name    =>  #string
        x_prop1         =>  #...
        x_prop2         =>  #...
    }

C<display_name> is gotten from the provider module itself.

The C<x_*> values are the current values of the provider properties,
as assembled from examining both the module defaults and any custom values
that have been saved. The C<x_> prefix is added at this function; for example,
if the module has a property C<foo>, this function will name that value as
C<x_foo>.

=cut

sub get_all_provider_info {
    Cpanel::Context::must_be_list();

    my $conf         = Cpanel::SSL::Auto::Config::Read->new();
    my $cur_provider = $conf->get_provider() // q<>;

    my $merge = Hash::Merge->new();

    my @infos;

    for my $mod_name ( Cpanel::SSL::Auto::Utils::get_provider_module_names() ) {
        try {
            my $ns = Cpanel::SSL::Auto::Loader::get_and_load($mod_name);
            unless ( try { $ns->is_obsolete() } ) {

                my $props_hr = $merge->merge(
                    { $conf->get_provider_properties($mod_name) },
                    { $ns->PROPERTIES() },
                );

                my $display_name = $ns->DISPLAY_NAME();

                push @infos, {
                    module_name  => $mod_name,
                    enabled      => ( $mod_name eq $cur_provider ) ? 1 : 0,
                    display_name => $display_name,
                    specs        => _assemble_specs($ns),
                    ( map { ( "x_$_" => $props_hr->{$_} ) } keys %$props_hr ),
                };
            }
        }
        catch {
            warn "Failed to load information for the AutoSSL module “$mod_name”: $_";
        };
    }

    return @infos;
}

sub _assemble_specs {
    my ($ns) = @_;

    my @dcv = ('http');
    push @dcv, 'dns' if $ns->USE_LOCAL_DNS_DCV();

    my $self_reported_specs = $ns->SPECS();

    my %specs = (
        (
            map { $_ => $ns->$_() }
              qw(
              SUPPORTS_ANCESTOR_DCV
              MAX_DOMAINS_PER_CERTIFICATE
              HTTP_DCV_MAX_REDIRECTS
              SUPPORTS_WILDCARD
              )
        ),
        DCV_METHODS => \@dcv,
    );

    my @self_keys_to_copy = (
        'VALIDITY_PERIOD',
        'RATE_LIMIT_CERTIFICATES_PER_REGISTERED_DOMAIN_PER_WEEK',
        'DELIVERY_METHOD',
        'AVERAGE_DELIVERY_TIME',
    );
    @specs{@self_keys_to_copy} = @{$self_reported_specs}{@self_keys_to_copy};
    return \%specs;
}

=head2 reset_provider( MODULE_NAME )

Reset the given provider--however the given module may define that action.

=cut

sub reset_provider {
    my ($provider) = @_;

    my $ns = Cpanel::SSL::Auto::Loader::get_and_load($provider);
    $ns->new()->RESET();

    return;
}

=head2 export_provider_properties( MODULE_NAME, KEY1 => VAL1, KEY2 => VAL2, .. )

Calls the provider module’s logic to “export” a given property
(e.g., to the provider’s own server). A useful application of this
is to send registration information or agreement to terms of service.

To validate the values that are being set, we need to check against the
locally saved provider properties. This means that that datastore
(i.e., C<Cpanel::SSL::Auto::Config> cannot be open when this gets called.

This will return the instance of C<Cpanel::SSL::Auto::Config> that was
used to validate the passed-in values.

=cut

sub export_provider_properties {
    my ( $provider, $conf, %props ) = @_;

    if ( !try { $conf->isa('Cpanel::SSL::Auto::Config::Read') } ) {
        die "2nd parameter must be a Config object, not “$conf”!";
    }

    Cpanel::SSL::Auto::Utils::validate_property_name($_) for keys %props;

    my $ns = Cpanel::SSL::Auto::Loader::get_and_load($provider);

    _verify_new_properties( $provider, $conf, \%props );

    $ns->new()->EXPORT_PROPERTIES(%props);

    return;
}

sub _verify_new_properties {
    my ( $provider, $conf, $props_hr ) = @_;

    my $ns = Cpanel::SSL::Auto::Loader::get_and_load($provider);

    my %default = $ns->PROPERTIES();

    if ( length $default{'terms_of_service'} ) {
        my %old_conf = $conf->get_provider_properties($provider);

        my %proposed = (
            %old_conf,
            %$props_hr,
        );

        my $needs_tos_update = !length $proposed{'terms_of_service_accepted'};

        $needs_tos_update ||= ( $proposed{'terms_of_service_accepted'} || 0 ) ne $default{'terms_of_service'};

        if ($needs_tos_update) {
            die Cpanel::Exception->create( 'You must accept the current terms of service ([_1]) to proceed.', [ $default{'terms_of_service'} ] );
        }
    }

    return;
}

1;
