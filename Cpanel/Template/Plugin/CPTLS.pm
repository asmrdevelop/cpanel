package Cpanel::Template::Plugin::CPTLS;

# cpanel - Cpanel/Template/Plugin/CPTLS.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Template::Plugin::CPTLS

=head1 SYNOPSIS

    USE CPTLS;

    SET certs = CPTLS.get_domain_tls_certificates('foo.example.com');

=head1 DESCRIPTION

This module is a L<Template::Plugin> subclass that provides access to
certain TLS configurations on the system.

=cut

#----------------------------------------------------------------------

use parent 'Template::Plugin';

use Cpanel::LoadModule ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 cpsrvd_serves_valid_tls( $DOMAIN )

This returns a boolean that indicates whether cpsrvd serves valid TLS
for $DOMAIN.

=cut

sub cpsrvd_serves_valid_tls ( $self, $domain ) {
    require Cpanel::LoadFile;
    require Cpanel::Server::TLSLookup;

    my ( $tls_domain, $is_domain_tls ) = Cpanel::Server::TLSLookup::get_domain_and_info($domain);

    return 0 if !$tls_domain;

    my $rdr = $is_domain_tls ? 'Cpanel::Domain::TLS' : 'Cpanel::Apache::TLS';
    Cpanel::LoadModule::load_perl_module($rdr);

    my $path = $rdr->get_certificates_path($tls_domain);

    my $pem = Cpanel::LoadFile::load($path);

    require Crypt::Format;
    my ( $leaf, @ca ) = Crypt::Format::split_pem_chain($pem);

    my $known_match = ( $domain =~ tr<.><> ) == ( $tls_domain =~ tr<.><> );

    if ( !$known_match ) {
        require Cpanel::SSL::Objects::Certificate;

        my $obj = Cpanel::SSL::Objects::Certificate->new( cert => $leaf );
        return 0 if !$obj->valid_for_domain($domain);
    }

    # Even if the certificate comes from Domain TLS, we don’t know that
    # the certificate hasn’t expired, been revoked, etc. To be on the safe
    # side, verify all certificate chains here.

    require Cpanel::SSL::Verify;

    return 0 if !Cpanel::SSL::Verify->new()->verify( $leaf, @ca )->ok();

    return 1;
}

1;
