package Cpanel::Exception::IO::SocketOpenError;

# cpanel - Cpanel/Exception/IO/SocketOpenError.pm  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use parent qw( Cpanel::Exception::IOError );

use Socket ();

use Cpanel::LocaleString ();

#cf. man 2 socket, checked against Socket.pm
#NOTE: exposed for tests only
our @_domains_to_check = qw(
  AF_UNIX
  AF_INET
  AF_INET6
  AF_X25
  AF_APPLETALK
);

#cf. man 2 socket, checked against Socket.pm
#NOTE: exposed for tests only
our @_types_to_check = qw(
  SOCK_STREAM
  SOCK_DGRAM
  SOCK_SEQPACKET
  SOCK_RAW
  SOCK_RDM
);

#Metadata propreties:
#   error
#   domain
#   type
#   protocol
#
sub _default_phrase {
    my ($self) = @_;

    my ( $domain, $type, $protocol, $error ) = map { $self->get($_) } qw(
      domain
      type
      protocol
      error
    );

    return Cpanel::LocaleString->new(
        'The system failed to open a socket of domain “[_1]” and type “[_2]” using the “[_3]” protocol because of an error: [_4]',
        $self->_get_human_DOMAIN($domain),
        $self->_get_human_TYPE($type),
        $self->_get_human_PROTOCOL($protocol),
        $error,
    );
}

sub _get_human_DOMAIN {
    my ( $self, $value ) = @_;

    if ( _is_whole_number($value) ) {
        return _check_value_against_socket_masks( $value, \@_domains_to_check );
    }

    return $value;    #unrecognized
}

sub _get_human_TYPE {
    my ( $self, $value ) = @_;

    if ( _is_whole_number($value) ) {
        return _check_value_against_socket_masks( $value, \@_types_to_check );
    }

    return $value;    #unrecognized
}

sub _get_human_PROTOCOL {
    my ( $self, $value ) = @_;

    return ( getprotobynumber $value )[0] || $value;
}

sub _check_value_against_socket_masks {
    my ( $value, $masks_ar ) = @_;

    for my $checking (@$masks_ar) {
        my $mask = Socket->can($checking)->();
        return $checking if ( $value & $mask ) == $mask;
    }

    return $value;
}

sub _is_whole_number {
    my ($value) = @_;

    return length($value) && $value =~ m<\A[0-9]+\z>;
}

1;
