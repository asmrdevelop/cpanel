package Cpanel::RSA;

# cpanel - Cpanel/RSA.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::RSA - convenience for general-purpose RSA key generation

=head1 SYNOPSIS

    use Cpanel::RSA ();

    my $rsa_str = Cpanel::RSA::generate_private_key_string();

    my $big_rsa_str = Cpanel::RSA::generate_private_key_string(8192);

=cut

use strict;
use warnings;

use Cpanel::Exception  ();
use Cpanel::LoadModule ();

use Cpanel::RSA::Constants ();

our $DEFAULT_KEY_SIZE;

BEGIN {
    *DEFAULT_KEY_SIZE = \$Cpanel::RSA::Constants::DEFAULT_KEY_SIZE;
}

sub generate_private_key_string {
    my ($size) = @_;

    $size ||= $DEFAULT_KEY_SIZE;

    if ( $size =~ tr<0-9><>c ) {
        die Cpanel::Exception::create( 'InvalidParameter', '“[_1]” is not a valid length for an [asis,RSA] key. This value must be a positive integer.', [$size] );
    }

    Cpanel::LoadModule::load_perl_module('Crypt::OpenSSL::RSA');
    my $str = 'Crypt::OpenSSL::RSA'->generate_key($size) or do {
        die "The system failed to generate an RSA key!";
    };

    $str = $str->get_private_key_string();
    chomp $str if defined $str;

    return $str;
}

1;
