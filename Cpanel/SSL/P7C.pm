package Cpanel::SSL::P7C;

# cpanel - Cpanel/SSL/P7C.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::SSL::P7C - Mine .p7c files for X.509 certificates

=head1 SYNOPSIS

    my @certs_pem = Cpanel::SSL::P7C::get_certificates( $der_or_pem );

=head1 DISCUSSION

Some CAs’ C<caIssuer> URLs return data in C<.p7c> format rather than just
giving the certificate. (Basically “abusing” the Cryptographic Message Syntax
format to use the certificates list as a payload.) This module parses that
format.

This data structure is documented at L<https://tools.ietf.org/html/rfc5652>.

If you think you need to build a parser for this format,
look at L<Test::SSL::P7C> in this repository (under F<t/lib>).

See also: L<http://security.stackexchange.com/questions/73156/whats-the-difference-between-x-509-and-pkcs7-certificate>

=head1 FUNCTIONS

=cut

use strict;
use warnings;

use Cpanel::Context ();
use Cpanel::OpenSSL ();
use Crypt::Format   ();

=head2 get_certificates( PEM_OR_DER )

Returns the certificates in the object as a list, each item of which is
in PEM format.

=cut

sub get_certificates {
    my ($pem_or_der) = @_;

    Cpanel::Context::must_be_list();

    my @args = (
        'pkcs7',
        '-print_certs',
    );

    if ( index( $pem_or_der, '-----' ) != 0 ) {
        push @args, '-inform' => 'DER';
    }

    #Forking to OpenSSL is slow, but it shouldn’t be
    #bad since this shouldn’t be called more than a few times each week.

    my $ossl = Cpanel::OpenSSL->new();

    my $run = $ossl->run(
        args  => \@args,
        stdin => $pem_or_der,
    );

    if ( $run->{'CHILD_ERROR'} ) {
        die "OpenSSL failed [@args]: $run->{'CHILD_ERROR'} (@{$run}{'stdout', 'stderr'})";
    }

    return map { Crypt::Format::normalize_pem($_) } $run->{'stdout'} =~ m<(-+BEGIN.+?END.+?-+)>sg;
}

1;
