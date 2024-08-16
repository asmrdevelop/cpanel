package Cpanel::CSP::Nonces;

# cpanel - Cpanel/CSP/Nonces.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Rand::Get ();

# 64-bit equivalent nonces in base64.
use constant NONCE_LEN => 11;

my $instance;

=head1 NAME

Cpanel::CSP::Nonces - nonce generator for Content-Security-Policy headers

=head1 DESCRIPTION

Cpanel::CSP::Nonces generates nonce values that are used to explicitly permit
inline JavaScript when enabling the Content-Security-Policy header.  Since a
malicious piece of JavaScript inserted due to XSS will not have a nonce, it will
not be able to execute, preventing the XSS attack from succeeding.

This class is a singleton; its instance can be accessed using the C<instance>
class method.

=head1 CLASS METHODS

=cut

sub _new {
    my ( $class, %args ) = @_;
    my $self = bless \%args, $class;
    $self->generate( $self->{num} // 32 );
    return $self;
}

=head2 instance

Return the singleton instance of this class, instantiating it if necessary.

This method also generates a new set of nonces; by default, 32 nonces are
created.

=cut

sub instance {
    my ( $class, %args ) = @_;
    return $instance ||= $class->_new(%args);
}

=head1 METHODS

=head2 generate($num)

Generate a new set of nonces, overwriting the old ones.

Returns undef.

=cut

sub generate {
    my ( $self, $num ) = @_;
    my $rand = Cpanel::Rand::Get::getranddata( NONCE_LEN * $num, [ 'A' .. 'Z', 'a' .. 'z', 0 .. 9, '+', '/' ] );
    $self->{cache} = [ map { substr( $rand, 0, NONCE_LEN, '' ) } ( 1 .. $num ) ];
    return;
}

=head2 nonce([$num])

Return the nonce indicated by C<$num>, which is 0-indexed.  Throw an exception
if there are not enough nonces.

Without an argument, returns a list of all the nonces.

=cut

sub nonce {
    my ( $self, $num ) = @_;
    return $self->{cache}->@* unless defined $num;
    die "Not enough nonces!" if $num >= scalar $self->{cache}->@*;
    return $self->{cache}->[$num];
}

*nonces = \&nonce;

1;
