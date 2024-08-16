package Cpanel::ASN1;

# cpanel - Cpanel/ASN1.pm                          Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::ASN1

=head1 DESCRIPTION

This works exactly like L<Convert::ASN1> except that the following methods will
throw an exception on failure:

=over 4

=item * C<prepare()>

=item * C<find()>

=item * C<decode()>

=item * C<encode()>

=back

As of now, the exception type is not specified; that should change if this
module sees more widespread use than just testing.

=cut

use parent 'Convert::ASN1';

sub prepare {
    my ( $self, $tmpl ) = @_;

    return $self->SUPER::prepare($tmpl) || do {
        die( ( ref $self ) . "::prepare($tmpl): " . $self->error() );
    };
}

sub find {
    my ( $self, $macro ) = @_;

    return $self->SUPER::find($macro) || do {
        die( ( ref $self ) . "::find($macro): " . $self->error() );
    };
}

sub decode {
    my ( $self, $pdu ) = @_;

    return $self->SUPER::decode($pdu) || do {
        die( ( ref $self ) . "::decode($pdu): " . $self->error() );
    };
}

sub encode {
    my ( $self, @vars ) = @_;

    return $self->SUPER::encode(@vars) || do {
        die( ( ref $self ) . "::encode(@vars): " . $self->error() );
    };
}

1;
