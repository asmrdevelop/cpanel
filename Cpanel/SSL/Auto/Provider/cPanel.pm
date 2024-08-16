package Cpanel::SSL::Auto::Provider::cPanel;

#                                      Copyright 2024 WebPros International, LLC
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited.

=pod

=encoding utf-8

=head1 NAME

Cpanel::SSL::Auto::cPanel - Minimal AutoSSL "provider" to identify cPanel-signed certs.

=head1 DESCRIPTION

This recognizes free, cPanel-signed certificates.

=cut

use cPstrict;

use parent qw(
  Cpanel::SSL::Auto::ObsoleteProvider
);

use Cpanel::OrDie         ();
use Cpanel::SSL::Identify ();
use Cpanel::SSL::Utils    ();

use constant {
    DAYS_TO_REPLACE => 15,
    DISPLAY_NAME    => 'Sectigo',
};

=head1 METHODS

=head2 CERTIFICATE_IS_FROM_HERE( PEM_STRING )

Indicates whether the PEM-encoded certificate comes from this provider.

=cut

sub CERTIFICATE_IS_FROM_HERE ( $self, $cert_pem ) {
    my $parse = Cpanel::OrDie::multi_return(
        sub { Cpanel::SSL::Utils::parse_certificate_text($cert_pem); },
    );

    return $self->CERTIFICATE_PARSE_IS_FROM_HERE($parse);
}

=head2 CERTIFICATE_PARSE_IS_FROM_HERE( C<Cpanel::SSL::Object::Certificate>->parsed() )

Indicates whether the pre-parsed certificate comes from this provider.

=cut

sub CERTIFICATE_PARSE_IS_FROM_HERE ( $self, $parse ) {
    return Cpanel::SSL::Identify::is_parsed_free_cpanel_90_day_cert($parse);
}

1;
