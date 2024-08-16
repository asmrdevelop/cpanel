package Cpanel::SSL::CheckPeer;

# cpanel - Cpanel/SSL/CheckPeer.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::CheckPeer

=head1 SYNOPSIS

    Cpanel::SSL::CheckPeer::check( 'myhost.com', 443 );

    Cpanel::SSL::CheckPeer::check( '3.45.194.5', 993, 'mail.somesite.com' );

=head1 DESCRIPTION

This module wraps up the logic for testing a peer host’s SSL connection.

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use IO::Socket::SSL ();

=head2 check( IP_OR_HOST, PORT, SNI_HOSTNAME )

Throws an exception if an SSL handshake with the indicated peer has a problem.
If SNI_HOSTNAME is not given, the value of IP_OR_HOST is used as the SNI
hostname.

Currently the thrown exception is an opaque string; hopefully at a later
point we can throw a typed exception that will offer a more machine-parsable
error.

=cut

#for testing
our $_IO_Socket_SSL_class = 'IO::Socket::SSL';

sub check {
    my ( $ip_or_hostname, $port, $servername ) = @_;

    #local()ize this here because IO::Socket::SSL sets $@ regardless
    #of whether there’s a failure or not.
    local $@;

    #Ideally we’d call into Net::SSLeay directly so we’d get an error
    #object rather than a string, but then we’d be responsible for
    #OCSP checking, name verification, etc. … all the stuff that
    #IO::Socket::SSL writes out manually. :-/
    #
    $_IO_Socket_SSL_class->new(
        PeerHost => $ip_or_hostname,
        PeerPort => $port,
        ( defined($servername) ? ( SSL_hostname => $servername ) : () ),
    ) or die $@;

    return;
}

1;
