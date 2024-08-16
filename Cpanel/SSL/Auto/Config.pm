package Cpanel::SSL::Auto::Config;

# cpanel - Cpanel/SSL/Auto/Config.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Config - local configuration for AutoSSL and providers

=head1 SYNOPSIS

    my $conf = Cpanel::SSL::Auto::Config->new();

    $conf->set_provider($module_name);

    $conf->set_provider_property($module_name, $name => $value);
    $conf->unset_provider_property($module_name, $name);

    $conf->set_metadata( property1 => 1, property2 => 0, .. );

    #This will be just what’s in the config; there is no knowledge
    #here of defaults from the provider module itself.
    my %props = $conf->get_provider_properties();

    $conf->disable();

    $conf->save_and_close();

=head1 DESCRIPTION

This module is here to provide read/write access to AutoSSL’s configuration.
It inherits all methods from L<Cpanel::SSL::Auto::Config::Read>.

=cut

use strict;
use warnings;

use parent qw( Cpanel::SSL::Auto::Config::Read );

use Cpanel::Exception               ();
use Cpanel::LoadModule              ();
use Cpanel::SSL::Auto::Utils        ();
use Cpanel::Transaction::File::JSON ();

# Shouldn’t be needed, but the include-dependencies checker whines otherwise.
use Cpanel::SSL::Auto::Config::Read ();

our ( $_CONF_PATH, @_default );
*_default = \@Cpanel::SSL::Auto::Config::Read::_default;

#overridden in tests
*_CONF_PATH = \$Cpanel::SSL::Auto::Config::Read::_CONF_PATH;

sub new {
    my ($class) = @_;

    #xaction, i.e., “transaction”
    my $xaction = Cpanel::Transaction::File::JSON->new(
        path => $_CONF_PATH,
    );

    if ( 'SCALAR' eq ref $xaction->get_data() ) {
        $xaction->set_data( {@_default} );
    }

    return bless { _xaction => $xaction }, $class;
}

sub _get_data {
    my ($self) = @_;
    return $self->{'_xaction'}->get_data();
}

sub save_and_close {
    my ($self) = @_;

    $self->{'_xaction'}->save_and_close_or_die();

    Cpanel::LoadModule::load_perl_module('Cpanel::ServerTasks');
    Cpanel::ServerTasks::schedule_task( ['CpDBTasks'], 5, 'build_global_cache' );

    return;
}

sub set_provider_property {
    my ( $self, $provider, $key, $value ) = @_;

    Cpanel::SSL::Auto::Utils::validate_property_name($key);

    $self->_validate_provider($provider);

    if ( ref $value ) {
        die Cpanel::Exception::create( 'InvalidParameter', 'This value can only be a string or a number.' );
    }

    $self->{'_xaction'}->get_data()->{'provider_properties'}{$provider}{$key} = $value;

    return;
}

sub unset_provider_property {
    my ( $self, $provider, $key ) = @_;

    Cpanel::SSL::Auto::Utils::validate_property_name($key);

    $self->_validate_provider($provider);

    delete $self->_get_data()->{'provider_properties'}{$provider}{$key};

    return;
}

sub set_provider {
    my ( $self, $provider ) = @_;

    $self->_validate_provider($provider);

    $self->_get_data()->{'provider'} = $provider;

    return $self;
}

sub set_metadata {
    my ( $self, %metadata ) = @_;

    _validate_metadata( \%metadata );

    my $meta_hr = $self->_get_data()->{'metadata'} ||= {};

    #NB: Use Hash::Merge if multi-level merge is ever needed.
    %$meta_hr = ( %$meta_hr, %metadata );

    return;
}

sub disable {
    my ($self) = @_;

    $self->_get_data()->{'provider'} = undef;

    return;
}

sub _validate_metadata {
    my ($metadata_hr) = @_;

    for my $k ( keys %$metadata_hr ) {
        if ( exists $Cpanel::SSL::Auto::Config::Read::metadata_defaults{$k} ) {
            if ( $metadata_hr->{$k} !~ m<\A[01]\z> ) {
                die "“$k” must be 0 or 1, not “$metadata_hr->{$k}”.";
            }
        }
        else {
            die "Unrecognized metadata key: “$k”";
        }
    }

    return;
}

1;
