package Cpanel::CommandStream::Client::WebSocket::APIToken;

# cpanel - Cpanel/CommandStream/Client/WebSocket/APIToken.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::CommandStream::Client::WebSocket::APIToken

=head1 SYNOPSIS

    my $remoteobj = Cpanel::CommandStream::Client::WebSocket::APIToken->new(
        hostname => 'some.remote.host',
        username => 'johnny',
        api_token => 'THISISMYAPITOKENDONOTSHAREIT',
        tls_verification => 'on',
    );

=head1 DESCRIPTION

This class subclasses L<Cpanel::CommandStream::Client::WebSocket> and
L<Cpanel::CommandStream::Client::WebSocket::Base::APIToken> to yield
an end class that authenticates via API token.

=head1 HANDY ONE-LINER

    perl -MCpanel::CommandStream::Client::WebSocket::APIToken -MCpanel::PromiseUtils -MData::Dumper -e'print Dumper( Cpanel::PromiseUtils::wait_anyevent( Cpanel::CommandStream::Client::WebSocket::APIToken->new( { hostname => "localhost", tls_verification => "off", username => "root", api_token => "XXXXX" } )->exec( command => ["hostname"] ) ) )'

=cut

#----------------------------------------------------------------------

use parent (
    'Cpanel::CommandStream::Client::WebSocket::Base::APIToken',
    'Cpanel::CommandStream::Client::WebSocket',
);

1;
