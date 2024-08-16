package Cpanel::cPStore::LicenseAuthn;

# cpanel - Cpanel/cPStore/LicenseAuthn.pm          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::cPStore::LicenseAuthn - cPStore client that uses license authentication

=head1 SYNOPSIS

    use Cpanel::cPStore::LicenseAuthn ();

    #an authenticated client;
    my $cps = Cpanel::cPStore::LicenseAuthn->new();

    #The following will all return the “data” and discard the “message”:
    my $get = $cps->get( $endpoint );
    my $delete = $cps->delete( $endpoint );
    my $post = $cps->post( $endpoint, key => value, ... );
    my $put = $cps->put( $endpoint, key => value, ... );

=head1 DESCRIPTION

All methods will throw exceptions on errors. This includes API failures,
which are reported via the C<Cpanel::Exception::cPStoreError> class. Actual
network failures or other kinds of problems, of course, will be reported via
other appropriate exception types.

=cut

use strict;
use warnings;

use parent 'Cpanel::cPStore';

use Cpanel::Exception    ();
use Cpanel::LicenseAuthn ();

sub new {
    my ($class) = @_;

    my $self = $class->SUPER::new();

    $self->enable_sending_license_auth();

    return bless $self, $class;
}

sub enable_sending_license_auth {
    my ($self) = @_;
    my ( $id, $secret ) = _get_license_authn_id_and_secret();

    if ( !length $id || !length $secret ) {
        die Cpanel::Exception::create( 'LicenseProvisionMissing', 'The system does not possess a valid license provisioning file, so it could not connect to the [asis,cPanel Store]. Run the “[_1]” command.', ['/usr/local/cpanel/cpkeyclt'] );
    }

    return $self->{'_http'}->set_default_header( 'Authorization', "License $id $secret" );
}

sub disable_sending_license_auth {
    my ($self) = @_;
    return $self->{'_http'}->delete_default_header('Authorization');
}

#overridden from tests
sub _get_license_authn_id_and_secret {
    return Cpanel::LicenseAuthn::get_id_and_secret('cpstore');
}

1;
