package Cpanel::ElFinder::Encoder;

# cpanel - Cpanel/ElFinder/Encoder.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

#use warnings;

our $VERSION = '1.0';

#-------------------------------------------------------------------------------------------------
# Purpose:  This module contains the special purpose encoder & decoder for the elfinder
# application path protection - identification scheme.
#-------------------------------------------------------------------------------------------------
# Developer Notes:
#  1) Elfinder documenation recommends that the path be encrypted before it is passed to the
#  encoder. We were unable to find a sufficiently efficient encrypter for the first revision
#  of this and rely on just the base encoding. We have left a stub for further development
#  to enhance this security model via an implementation in the _encrypt and _decrypt methods.
#-------------------------------------------------------------------------------------------------
# TODO:
#-------------------------------------------------------------------------------------------------

# Cpanel Dependencies
use Cpanel::Locale           ();
use Cpanel::StringFunc::Trim ();

# Globals
my $locale;

#-------------------------------------------------------------------------------------------------
# Name:
#   initialize
# Desc:
#   Initialize the file path encoder.
# Arguments:
#   N/A
# Returns:
#   true if successful, false otherwise.
#-------------------------------------------------------------------------------------------------
sub initialize {
    eval "require MIME::Base64;";
    if ($@) {
        _initialize();
        return ( 0, $locale->maketext( 'Unable to load the MIME::Base64 library with the following error: [_1]', $@ ) );
    }
    return ( 1, '' );
}

#-------------------------------------------------------------------------------------------------
# Name:
#   encode_path
# Desc:
#   Encodes a path into the key.
# Arguments:
#   string - path stored in key.
# Returns:
#   string - key with the path stored in it in a reversible encoding.
#-------------------------------------------------------------------------------------------------
sub encode_path {
    my ($path) = @_;
    my $key;

    my $protected_path = _encrypt($path);

    $key = MIME::Base64::encode_base64( $protected_path, '' );
    $key =~ tr/+\/=/-_./;
    $key = Cpanel::StringFunc::Trim::rtrim( $key, '\.' );

    return $key;
}

#-------------------------------------------------------------------------------------------------
# Name:
#   decode_path
# Desc:
#   Decodes a path from the key.
# Arguments:
#   string - encoded path stored in a key.
# Returns:
#   string - clear text path.
#-------------------------------------------------------------------------------------------------
sub decode_path {
    my ($key) = @_;
    my $path;

    $key .= "." x ( 4 - ( length($key) % 4 ) );    # expand to fill 4 byte boundary
    $key =~ tr/-_./+\/=/;
    $path = MIME::Base64::decode_base64($key);

    return _decrypt($path);
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _initialize
# Desc:
#   initialize the local system if they are not already initialized.
# Arguments:
#   N/A
# Returns:
#   N/A
#-------------------------------------------------------------------------------------------------
sub _initialize {
    $locale ||= Cpanel::Locale->get_handle();
    return 1;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _decrypt
# Desc:
#   Stub to decrypt the decoded key.
# Arguments:
#   string - encrypted key to decrypt with out other encoding.
# Returns:
#   string - path
#-------------------------------------------------------------------------------------------------
sub _decrypt {
    my ($key) = @_;
    return $key;
}

#-------------------------------------------------------------------------------------------------
# Scope:
#   private (by convention)
# Name:
#   _encrypt
# Desc:
#   Stub to encrypt the path prior to encoding.
# Arguments:
#   string - path.
# Returns:
#   string - encrypted path.
#-------------------------------------------------------------------------------------------------
sub _encrypt {
    my ($path) = @_;
    return $path;
}

1;
