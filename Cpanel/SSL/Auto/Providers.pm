package Cpanel::SSL::Auto::Providers;

# cpanel - Cpanel/SSL/Auto/Providers.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::Providers - check data (certs) against all AutoSSL providers

=head1 SYNOPSIS

  use Cpanel::SSL::Auto::Providers ();
  use Cpanel::SSL::Objects::Certificate::File ();

  my $installed_autossl_providers = Cpanel::SSL::Auto::Providers->new();

  my $cert_obj = Cpanel::SSL::Objects::Certificate::File->new('path' => '/PATH/TO/CERT/PEM');

  my $provider_obj = $installed_autossl_providers->get_provider_object_for_certificate($cert_obj);

=cut

#----------------------------------------------------------------------

use strict;
use warnings;
use Cpanel::SSL::Auto::Loader ();
use Cpanel::SSL::Auto::Utils  ();

=head2 new

Creates a Cpanel::SSL::Auto::Providers providers object that
can be used to fetch individual provider modules.

Warning: This will load all installed provider object modules
into memory.

=cut

sub new {
    my ($class) = @_;

    my @providers    = Cpanel::SSL::Auto::Utils::get_provider_module_names();
    my %provider_obj = map { $_ => Cpanel::SSL::Auto::Loader::get_and_load($_) } @providers;
    $_ = $_->new() for values %provider_obj;

    return bless { 'provider_objects' => \%provider_obj }, $class;

}

=head2 get_provider_object_by_module_name($provider_module_name)

Returns the provider object for a given module name
or dies.

=cut

sub get_provider_object_by_module_name {
    my ( $self, $provider_module_name ) = @_;

    my $p_obj = $self->{'provider_objects'}{$provider_module_name};

    $p_obj or die "Unknown AutoSSL provider “$provider_module_name”";

    return $p_obj;
}

=head2 get_provider_object_for_certificate_object(Cpanel::SSL::Objects::Certificate)

Return the provider object that issued a given certficate
represented by the passed in Cpanel::SSL::Objects::Certificate.

If no installed provider issued the certificate, this function
returns undef.

=cut

# $cert_ssl_obj must be a Cpanel::SSL::Object::Certificate
sub get_provider_object_for_certificate_object {
    my ( $self, $cert_ssl_obj ) = @_;

    #...the existing cert is from an AutoSSL provider
    for my $p_obj ( values %{ $self->{'provider_objects'} } ) {
        if ( $p_obj->can('CERTIFICATE_PARSE_IS_FROM_HERE') ) {
            return $p_obj if $p_obj->CERTIFICATE_PARSE_IS_FROM_HERE( $cert_ssl_obj->parsed() );
        }
        else {
            return $p_obj if $p_obj->CERTIFICATE_IS_FROM_HERE( $cert_ssl_obj->text() );
        }
    }

    return undef;    # Cert object is not autossl
}

1;
