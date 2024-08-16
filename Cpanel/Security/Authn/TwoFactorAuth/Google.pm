package Cpanel::Security::Authn::TwoFactorAuth::Google;

# cpanel - Cpanel/Security/Authn/TwoFactorAuth/Google.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use base qw(Cpanel::Security::Authn::TwoFactorAuth::Base);
use Try::Tiny;

use Cpanel::LoadModule ();

sub generate_random_base32_secret {
    require Cpanel::Rand::Get;
    return Cpanel::Rand::Get::getranddata( 16, [ 'A' .. 'Z', 2 .. 7 ] );
}

# References:
# https://github.com/google/google-authenticator/blob/master/libpam/google-authenticator.c#L48
# http://blog.tinisles.com/2011/10/google-authenticator-one-time-password-algorithm-in-javascript/
# https://metacpan.org/source/GRYPHON/Auth-GoogleAuth-1.01/lib/Auth/GoogleAuth.pm#L53
# http://tools.ietf.org/html/rfc6238
sub generate_code {
    my ( $self, $time_to_use ) = @_;

    Cpanel::LoadModule::load_perl_module('Digest::SHA');
    Cpanel::LoadModule::load_perl_module('MIME::Base32');

    $time_to_use ||= time;    # Default to the 'current' time.
    my $secret = $self->secret();

    # Step 1 - Decode the secret.
    #
    # The secret is a base32 value to start.
    my $key = MIME::Base32::decode_rfc3548($secret);

    # Step 2 - Generate the padded time value
    #
    # This is the time value divided by 30 seconds, padded to 16 chars, and
    # pack'ed it into a binary value.
    my $padded_time = pack( 'H*', sprintf( '%016x', int( $time_to_use / 30 ) ) );

    # Step 3 - Generate the HMAC-SHA1 for the key and the padded time.
    #
    # hmac_sha1_hex returns the HMAC as a hexadecimal string - containing
    # 20 bytes, and 40 hex chars.
    my $hmac = Digest::SHA::hmac_sha1_hex( $padded_time, $key );

    # Step 4 - Find the 'offset' for dynamically truncating the HMAC.
    #
    # This is value of the last 4 bits of the HMAC - we multiply it by 2, as
    # we are working with the hexadecimal value rather than the binary, to
    # get the 'correct' offset.
    my $offset = hex( substr( $hmac, -1 ) ) * 2;

    # Step 5 - Using the offset, truncate the HMAC
    #
    # The truncated HMAC is the value of 4 bytes from the offset
    # we determined in the previous step. (4 bytes = 8 chars of the hexadecimal string).
    my $truncated_hmac = hex( substr( $hmac, $offset, 8 ) );

    # Step 6 - Zero-out the most significant bit from 32 bits we just grabbed
    $truncated_hmac = $truncated_hmac & 0x7FFFFFFF;

    # Step 7 - Return the OTP.
    #
    # The OTP is the truncated hmac mod 1000000, padded with 0s for the length of 6 chars
    return sprintf( '%06d', $truncated_hmac % 1000000 );
}

sub _validate_secret {
    my $value = shift;

    Cpanel::LoadModule::load_perl_module('MIME::Base32');
    my $error;
    try {
        die 'Non-base32 characters found' if $value =~ tr/a-zA-Z2-7//c;
        MIME::Base32::decode_rfc3548($value);
    }
    catch {
        $error = $_;
    };

    return if $error;
    return 1;
}

1;
