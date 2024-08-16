package Cpanel::CheckPass::UNIX;

# cpanel - Cpanel/CheckPass/UNIX.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

require 5.010;    # For //

use strict;
use Crypt::Passwd::XS ();

our $VERSION = '1.2';

*unix_md5_crypt = \&Crypt::Passwd::XS::unix_md5_crypt;

sub checkpassword {
    my ( $password, $cryptedpassword ) = @_;
    if ( !defined $password || !defined $cryptedpassword || $password eq '' || $cryptedpassword eq '' || $cryptedpassword =~ /^\!/ || $cryptedpassword =~ /^\*/ ) { return (0); }

    if ( $cryptedpassword =~ /^(?:[^\$]|\$(?:[156]|apr1)\$)/ ) {
        if ( Crypt::Passwd::XS::crypt( $password, $cryptedpassword ) eq $cryptedpassword ) {
            return (1);
        }
    }
    else {
        # crypt scheme that is not currently supported by Crypt::Passwd::XS
        if ( ( crypt( $password, $cryptedpassword ) // '' ) eq $cryptedpassword ) {
            return (1);
        }
    }
    return (0);
}

sub getsalt {
    my ($cpass) = @_;

    $cpass =~ m/^
      \$
      (?:[156]|apr1)     # md5, sha-256, or sha-512, or "apr1 md5"; ignore blowfish
      \$
      (?:                # optional rounds count for sha-256 and sha-512,
          rounds=\d+     # not included with returned salt
          \$
      )?
      ([^\$]+)           # the salt itself
      \$
      [^\$]+             # the hashed password
      $/x and return $1;

    $cpass =~ /^([\.\/0-9A-Za-z]{2})[\.\/0-9A-Za-z]{11}$/ and return $1;    # DES crypt

    return undef;                                                           # better to return undef than to return something incorrect
}

1;
