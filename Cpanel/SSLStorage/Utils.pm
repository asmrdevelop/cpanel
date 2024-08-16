package Cpanel::SSLStorage::Utils;

# cpanel - Cpanel/SSLStorage/Utils.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Digest::MD5              ();
use Cpanel::SSL::Utils       ();
use Cpanel::WildcardDomain   ();
use Cpanel::Crypt::Algorithm ();

#NOTE: Here are the conventions for determining IDs.
#All times in UTC UNIXTIME.
#
#   RSA:
#   key = modfirst5_modlast5_modmd5.key
#   crt = subjCN_modfirst5_modlast5_notvalidbeforetime_asciimd5.crt
#   csr = CN_modfirst5_modlast5_asciimd5.csr
#
#   ECDSA:
#   key = ec- _ pubx_first10 _ md5( pub . curve_oid ) .key
#   crt = ec- _ subjCN _ pubx_first10 _ notvalidbeforetime _ asciimd5 .crt
#   csr = ec- _ CN _ pubx_first10 _ asciimd5 .csr
#
#   cabundle = leafOrgName_leafSubjectMD5_leafNotvalidbeforetime.cabundle

our $KEY_ID_REGEXP      = '(?:[0-9a-f]{5}_[0-9a-f]{5}_[0-9a-f]{32}|ec-[0-9a-f]{10}_[0-9a-f]{32})';
our $CERT_ID_REGEXP     = '(?:[a-zA-Z0-9_]+_[0-9a-f]{5}_[0-9a-f]{5}_[0-9]+_[0-9a-f]{32}|ec-[a-zA-Z0-9_]+_[0-9a-f]{10}_[0-9]+_[0-9a-f]{32})';
our $CSR_ID_REGEXP      = '(?:[a-zA-Z0-9_]+_[0-9a-f]{5}_[0-9a-f]{5}_[0-9a-f]{32}|ec-[a-zA-Z0-9_]+_[0-9a-f]{10}_[0-9a-f]{32})';
our $CABUNDLE_ID_REGEXP = '[a-zA-Z0-9_]+_[0-9a-f]{32}_[0-9]+';
our $MODULUS_REGEXP     = '[0-9a-f]+';

# make_key_id accepts any of the following:
# PEM
# A parsed key via Cpanel::SSL::Utils::parse_key_text
my $last_rsa_key_id;
my $last_rsa_modulus;

sub make_key_id {
    my ($key) = @_;
    return if !$key;

    my $parsed;
    if ( ref $key ) {
        $parsed = $key;
    }
    else {
        ( my $ok, $parsed ) = Cpanel::SSL::Utils::parse_key_text($key);
        return ( 0, $parsed ) if !$ok;
    }

    return Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parsed,
        rsa => sub {
            if ( !$last_rsa_modulus || ( $last_rsa_modulus ne $parsed->{'modulus'} ) ) {
                $last_rsa_modulus = $parsed->{'modulus'};
                $last_rsa_key_id  = _rsa_key_id( $parsed->{'modulus'} );
            }

            return ( 1, $last_rsa_key_id );
        },
        ecdsa => sub {
            return ( 1, _ecdsa_key_id($parsed) );
        },
    );
}

sub _rsa_key_id {
    my ($modulus_hex) = @_;

    #
    # We md5 the modulus rather than the whole key since the key
    # can be stored in different formats.
    #
    return join(
        '_',
        _extract_modulus_ends($modulus_hex),
        Digest::MD5::md5_hex($modulus_hex),
    );
}

sub _ecdsa_key_id {
    my ($ecdsa_hr) = @_;

    return join(
        '_',
        'ec-' . substr( $ecdsa_hr->{'pub_x'}, 0, 10 ),

        #
        # We md5 the individual pieces rather than the whole key for
        # the same reason why we do similarly for RSA.
        #
        Digest::MD5::md5_hex( join q<_>, @{$ecdsa_hr}{qw( pub_x pub_y curve_oid )} ),
    );
}

# We frequently call make_certificate_id
# when dealing with a certificate so we remember
# the last call to this function in memory
# to avoid the expensive parse and calculate
# when we call with the same certificate via
# various callers
my $last_certificate_id;
my $last_certificate_pem;

# make_certificate_id accepts any of the following:
# PEM
# Cpanel::SSL::Objects::Certificate instance
#
# The second argument is a parsed certificate via Cpanel::SSL::Utils::parse_certificate_text
sub make_certificate_id {
    my ( $cert, $parsed ) = @_;
    return if !$cert;

    my ( $cn, $modulus, $ec_public, $not_after, $pem );

    #Cpanel::SSL::Objects::Certificate instance
    if ( ref $cert ) {
        $pem = $cert->text();
        return ( 1, $last_certificate_id ) if $last_certificate_pem && $last_certificate_pem eq $pem;
        $cn        = $cert->domain();
        $modulus   = $cert->modulus();
        $ec_public = $cert->ecdsa_public();
        $not_after = $cert->not_after();
    }

    #PEM
    else {
        return ( 1, $last_certificate_id ) if $last_certificate_pem && $last_certificate_pem eq $cert;
        if ( !$parsed ) {
            ( my $ok, $parsed ) = Cpanel::SSL::Utils::parse_certificate_text($cert);
            return ( 0, $parsed ) if !$ok;
        }

        $cn = $parsed->{'subject'}{'commonName'};
        if ( !defined $cn ) {
            $cn = q{};
        }

        $modulus   = $parsed->{'modulus'};
        $ec_public = $parsed->{'ecdsa_public'};
        $not_after = $parsed->{'not_after'};
        $pem       = $cert;
    }

    my $cn_fs = _fs_format($cn);

    $last_certificate_pem = $pem;

    if ($modulus) {
        my @modulus_ends = _extract_modulus_ends($modulus);
        $last_certificate_id = join( '_', $cn_fs, @modulus_ends, $not_after, Digest::MD5::md5_hex( Cpanel::SSL::Utils::normalize($pem) ) );
    }
    elsif ($ec_public) {
        $last_certificate_id = join(
            '_',
            "ec-$cn_fs",
            substr( $ec_public, 2, 10 ),
            $not_after,
            Digest::MD5::md5_hex( Cpanel::SSL::Utils::normalize($pem) ),
        );
    }
    else {
        die "Unknown encryption type!";
    }

    return ( 1, $last_certificate_id );
}

sub make_csr_id {
    my $csr = shift or return;

    my ( $ok, $parsed ) = Cpanel::SSL::Utils::parse_csr_text($csr);
    return ( 0, $parsed ) if !$ok;

    #TODO: Update this to use the 'domains' array?
    my $cn = $parsed->{'commonName'};
    if ( !defined $cn ) {
        $cn = q{};
    }

    my $cn_fs = _fs_format($cn);

    return Cpanel::Crypt::Algorithm::dispatch_from_parse(
        $parsed,
        rsa => sub {
            my @modulus_ends = _extract_modulus_ends( $parsed->{'modulus'} );

            return ( 1, join( '_', $cn_fs, @modulus_ends, Digest::MD5::md5_hex( Cpanel::SSL::Utils::normalize($csr) ) ) );
        },
        ecdsa => sub {
            return (
                1,
                join(
                    '_',
                    "ec-$cn_fs",
                    substr( $parsed->{'ecdsa_public'}, 2, 10 ),
                    Digest::MD5::md5_hex( Cpanel::SSL::Utils::normalize($csr) ),
                )
            );
        },
    );
}

sub make_cabundle_id {
    my $cab = shift or return undef;

    my ( $ok, $leaf ) = Cpanel::SSL::Utils::find_leaf_in_cabundle($cab);
    return ( 0, $leaf ) if !$ok;

    return (
        1,
        join(
            '_',
            _fs_format( $leaf->{'parsed'}{'subject'}{'organizationName'} ),
            scalar Digest::MD5::md5_hex( $leaf->subject_text() ),
            $leaf->{'parsed'}{'not_after'},
        ),
    );
}

sub _extract_modulus_ends {
    my ($mod) = @_;

    $mod =~ m{\A(.{5}).*(.{5})\z};

    return ( $1, $2 );
}

#Replace a leading * with "_wildcard_".
#Then, reduce all [^_a-zA-Z0-9]+ to a single _.
my $_fs_weird = '[^_a-zA-Z0-9]';

sub _fs_format {
    my $in = shift;

    # paths should be wildcard encoded
    $in = Cpanel::WildcardDomain::encode_wildcard_domain($in);

    $in =~ s{$_fs_weird+}{_}og;

    return $in;
}

sub _time { return time }    #for testing

1;

__END__

=encoding utf-8

=head1 NAME

Cpanel::SSLStorage::Utils - Utilities for SSLStorage

=head1 DESCRIPTION

This module’s functions are for use in the SSLStorage modules.
They should not be called from outside SSLStorage.

=head1 SYNOPSIS

    use Cpanel::SSLStorage::Utils ();

    my ( $key_ok, $key_id ) = Cpanel::SSLStorage::Utils::make_key_id( $key_in_pem_format );
    die $key_id if !$key_ok;

    my ( $crt_ok, $crt_id ) = Cpanel::SSLStorage::Utils::make_certificate_id( $crt_in_pem_format );
    die $crt_id if !$crt_ok;

    my ( $csr_ok, $csr_id ) = Cpanel::SSLStorage::Utils::make_csr_id( $csr_in_pem_format );
    die $csr_id if !$csr_ok;

    my ( $cab_ok, $cab_id ) = Cpanel::SSLStorage::Utils::make_cabundle_id( $cab_in_pem_format );
    die $cab_id if !$cab_ok;

=head1 SUBROUTINES

=over

=item make_key_id

=item make_certificate_id

=item make_csr_id

=item make_cabundle_id

=back

Each of these functions creates a filesystem-safe ID for the given SSL object.
They return ( 1, $id ) on success and ( 0, $error_message ) on failure.

The ID is determined solely by the content of the passed-in object. If two
objects have the same ID, then they are the same object, and any two objects
with different IDs are not the same.

NOTE: The format of the IDs is not defined. Do not build code that parses IDs!
