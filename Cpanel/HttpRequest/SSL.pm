package Cpanel::HttpRequest::SSL;

# cpanel - Cpanel/HttpRequest/SSL.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use base qw{ Cpanel::HttpRequest };

# NOTE: For this module to validate a certificate that a site is using, you must
#     include the certificate in /usr/local/cpanel/share/ssl/certs and properly
#     symlink the certificate's hash in the chain order as documented here:
#         http://www.openssl.org/docs/ssl/SSL_CTX_load_verify_locations.html

use strict;

our $VERSION = '1.0';

sub new {
    my ( $class, %p_options ) = @_;

    # sanity and strip our options #
    my $verify_hostname = defined $p_options{'verify_hostname'} ? delete $p_options{'verify_hostname'} : 1;

    my $self = $class->SUPER::new(%p_options);

    # setup our specific options #
    $self->{'ssl_options'} = { 'verify_hostname' => $verify_hostname };

    return bless $self, $class;
}

sub _socket_default_port {
    my $self = shift;
    return ( getservbyname( 'https', 'tcp' ) )[2];
}

sub _fetcher {
    my ( $self, $timeout, %params ) = @_;
    return $self->SUPER::_fetcher( $timeout, %params, verify_SSL => $self->{'ssl_options'}{'verify_hostname'} );
}

sub _initrequest {
    my ( $self, %params ) = @_;
    my $url = $self->SUPER::_initrequest(%params);
    return $url unless length $url;
    $url =~ s/^http:/https:/;
    return $url;
}

1;
