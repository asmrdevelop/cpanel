package Cpanel::SSL::Auto::Config::Read;

# cpanel - Cpanel/SSL/Auto/Config/Read.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Config::Read

=head1 SYNOPSIS

    my $conf_obj = Cpanel::SSL::Auto::Config::Read->new();

    my $metadata_hr = $conf_obj->get_metadata();

    my $provider = $conf_obj->get_provider();

    my %props = $conf_obj->get_provider_properties();

=head1 DESCRIPTION

This module is here to provide read-only access to AutoSSL’s configuration.

=cut

use Cpanel::Context                       ();
use Cpanel::LoadModule                    ();
use Cpanel::Transaction::File::JSONReader ();

use constant METADATA_BOOLEAN_DEFAULTS => (

    # Fired after DAYS_TO_RENEW/2.
    # Every domain fails DCV; cert can never renew
    'notify_autossl_expiry'      => 1,
    'notify_autossl_expiry_user' => 1,

    # Fired after DAYS_TO_RENEW/2.
    # Some or all currently secured domains fail DCV,
    # but at least one vhost domain passes. Cert will
    # eventually renew with at least some loss of covered domains,
    # though it may not be a net loss.
    'notify_autossl_expiry_coverage'      => 1,
    'notify_autossl_expiry_coverage_user' => 1,

    # Some or all currently secured domains fail DCV.
    # Cert doesn’t need to be renewed yet, so no renewal.
    'notify_autossl_renewal_coverage'      => 1,
    'notify_autossl_renewal_coverage_user' => 1,

    # A new certificate has been installed, and it’s awesome.
    'notify_autossl_renewal'      => 0,
    'notify_autossl_renewal_user' => 0,

    # New cert installed, but reduced coverage (likely from DCV failure).
    'notify_autossl_renewal_coverage_reduced'      => 1,
    'notify_autossl_renewal_coverage_reduced_user' => 1,

    # New cert installed, but it’s not all it could be (i.e., the vhost
    # has domains that the certificate doesn’t--likely from DCV failure).
    'notify_autossl_renewal_uncovered_domains'      => 1,
    'notify_autossl_renewal_uncovered_domains_user' => 1,

    'clobber_externally_signed' => 0,
);

our %metadata_defaults;
our $_CONF_PATH;

our @_default;

BEGIN {
    %metadata_defaults = METADATA_BOOLEAN_DEFAULTS();

    #overridden in tests
    $_CONF_PATH = '/var/cpanel/autossl.json';

    @_default = (
        _schema_version => 1,
        provider        => undef,
    );
}

=head1 METHODS

=head2 I<CLASS>->new()

Instantiates this class and returns the new instance.

=cut

sub new {
    my ($class) = @_;

    #xaction, i.e., “transaction”
    my $xaction = Cpanel::Transaction::File::JSONReader->new(
        path => $_CONF_PATH,
    );

    my $data = $xaction->get_data();
    $data = _default_data() if 'SCALAR' eq ref $data;

    return bless { _data => $data }, $class;
}

=head2 I<OBJ>->get_provider()

Returns the provider name (e.g., C<letsencrypt>) as a string.

=cut

sub get_provider {
    my ($self) = @_;

    return $self->_get_data()->{'provider'};
}

=head2 I<OBJ>->get_provider_properties()

Returns the provider properties as a list of key/value pairs.

This will be just what’s in the config; there is no knowledge
here of defaults from the provider module itself.

=cut

sub get_provider_properties {
    my ( $self, $provider ) = @_;

    Cpanel::Context::must_be_list();

    $self->_validate_provider($provider);

    my $props = $self->_get_data()->{'provider_properties'}{$provider};

    return $props ? %$props : ();
}

=head2 I<OBJ>->get_metadata()

Returns the AutoSSL metadata as a hash reference.

=cut

sub get_metadata {
    my ($self) = @_;

    my $cloned_data = $self->_get_cloned_data();

    $cloned_data = $cloned_data->{'metadata'} ||= {};

    foreach my $default ( keys %metadata_defaults ) {
        if ( !exists $cloned_data->{$default} ) {
            $cloned_data->{$default} = $metadata_defaults{$default};
        }
    }

    return $cloned_data;
}

#----------------------------------------------------------------------

sub _default_data {
    return {@_default};
}

sub _get_data {
    my ($self) = @_;

    return $self->{'_data'};
}

sub _get_cloned_data {
    my ($self) = @_;

    Cpanel::LoadModule::load_perl_module('Clone');

    return Clone::clone( $self->_get_data() );
}

sub _validate_provider {
    my ( undef, $specimen ) = @_;

    Cpanel::LoadModule::load_perl_module('Cpanel::SSL::Auto::Utils');

    return Cpanel::SSL::Auto::Utils::provider_exists_or_die($specimen);
}

1;
