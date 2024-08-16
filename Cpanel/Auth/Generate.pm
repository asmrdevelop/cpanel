package Cpanel::Auth::Generate;

# cpanel - Cpanel/Auth/Generate.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::Auth ();
use Cpanel::Rand::Get    ();
use Crypt::Passwd::XS    ();

our $VERSION = 1.1;

sub generate_password_hash {
    my ($cleartext_pass) = @_;

    my $crypted_hash                      = '*';
    my $system_cleartext_passwd_algorithm = Cpanel::Config::Auth::fetch_system_passwd_algorithm();
    my @valid_salt_chars                  = ( 'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '/' );

    # SHA-512/256 has a 256bit output size
    # so we need a salt length of 256bits (256/8)
    # See https://en.wikipedia.org/wiki/SHA-2
    my $random = Cpanel::Rand::Get::getranddata( 256 / 8, \@valid_salt_chars );

    if ( 'sha512' eq $system_cleartext_passwd_algorithm ) {
        $crypted_hash = Crypt::Passwd::XS::unix_sha512_crypt( $cleartext_pass, $random );
    }
    elsif ( 'sha256' eq $system_cleartext_passwd_algorithm ) {
        $crypted_hash = Crypt::Passwd::XS::unix_sha256_crypt( $cleartext_pass, $random );
    }
    else {    # default to md5 since no system we support lacks support for md5 crypt
        $crypted_hash = Crypt::Passwd::XS::unix_md5_crypt( $cleartext_pass, $random );
    }

    $crypted_hash =~ s/[\r\n]//g if $crypted_hash =~ tr{\r\n}{};

    return $crypted_hash;
}

1;
