package Cpanel::HttpUtils::SSL::Stapling;

# cpanel - Cpanel/HttpUtils/SSL/Stapling.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::HttpUtils::SSL::Stapling

=head1 DESCRIPTION

Utility functions to query the web server for OCSP stapling functionality.

=head1 BACKGROUND

OCSP Stapling (RFC 6066 - TLS Certificate Status Request extension) is an alternative
to OCSP certificate revocation checking.  With OCSP, the client is required to
validate the server's certificate by also connecting to the associated CA.  This implies
large bandwidth utilization for CAs, since each connecting client must also connect
to the CA.

Rather than forcing clients to perform separate requests, the web server now passes
along (e.g. stapled) an additional CA-signed timestamp.  This gives the client the
ability to validate a server certificate with a single TLS handshake to the server,
and make the appropriate decision based on the response (or lack thereof).

=head1 API

=cut

use strict;
use warnings;

use Cpanel::Version::Compare             ();
use Cpanel::ConfigFiles::Apache::modules ();

my $IS_STAPLING_SUPPORTED;

=head2 is_stapling_supported

Determines if the Apache web server can support OCSP Stapling.

Returns boolean 1 or 0.

=cut

sub is_stapling_supported {
    if ( !defined $IS_STAPLING_SUPPORTED ) {

        # RFC support added in 2.4.0: http://archive.apache.org/dist/httpd/CHANGES_2.4
        my $apver = Cpanel::ConfigFiles::Apache::modules::apache_long_version();
        $IS_STAPLING_SUPPORTED = Cpanel::Version::Compare::compare( $apver, '>=', '2.4.0' );
        $IS_STAPLING_SUPPORTED &&= Cpanel::ConfigFiles::Apache::modules::is_supported('mod_ssl');
    }

    $IS_STAPLING_SUPPORTED ||= 0;

    return $IS_STAPLING_SUPPORTED;
}

#For testing purposes only.
sub _reset_is_stapling_supported {
    $IS_STAPLING_SUPPORTED = undef;

    return;
}

=head1 LIMITATIONS

This only supports the Apache web server.

=cut

1;
