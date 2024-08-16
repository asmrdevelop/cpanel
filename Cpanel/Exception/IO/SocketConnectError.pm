package Cpanel::Exception::IO::SocketConnectError;

# cpanel - Cpanel/Exception/IO/SocketConnectError.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::ErrnoBase );

use Cpanel::LocaleString ();

use Cpanel::Socket::Constants ();
use Cpanel::Socket::Micro     ();

#Metadata propreties:
#   error
#   to
#
sub _default_phrase {
    my ($self) = @_;

    my $to;

    my ( $type, @sockdata ) = ( $self->get('type'), $self->get('socket') );
    ( $type, @sockdata ) = Cpanel::Socket::Micro::unpack_sockaddr_of_any_type( $self->get('to') )
      if !$type && $self->get('to');

    if ( $type eq $Cpanel::Socket::Constants::AF_UNIX ) {
        $to = $sockdata[0];

        return Cpanel::LocaleString->new(
            'The system failed to connect a [asis,UNIX] domain socket to “[_1]” because of an error: [_2]',
            $to,
            $self->get('error'),
        );
    }

    my $addr;
    if ( $type eq $Cpanel::Socket::Constants::AF_INET ) {
        $addr = Cpanel::Socket::Micro::inet_ntoa( $sockdata[1] );
    }
    elsif ( $type eq $Cpanel::Socket::Constants::AF_INET6 ) {
        $addr = Cpanel::Socket::Micro::inet6_ntoa( $sockdata[1] );
    }
    elsif ( $type eq $Cpanel::Socket::Constants::AF_UNIX ) {
        $addr = $sockdata[1];
    }
    else {
        $addr = "unknown address";
    }

    return Cpanel::LocaleString->new(
        'The system failed to connect an Internet socket to port “[_1]” of “[_2]” because of an error: [_3]',
        $sockdata[0],
        $addr,
        $self->get('error'),
    );
}

1;
