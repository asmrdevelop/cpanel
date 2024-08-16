package Cpanel::Encoder::URI;

# cpanel - Cpanel/Encoder/URI.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

BEGIN {
    eval {
        local $SIG{'__DIE__'};
        local $ENV{'PERL_URI_XSESCAPE'} = 0;
        require    # Cpanel::Static OK - optional package
          URI::XSEscape;
    };
    if ($@) {
        require Cpanel::URI::Escape::Fast;
        *uri_encode_str = *Cpanel::URI::Escape::Fast::uri_escape;
        *uri_decode_str = *_uri_decode_str_slow;
    }
    else {
        *uri_encode_str = *_uri_encode_str_fast;
        *uri_decode_str = *_uri_decode_str_fast;
    }

}

our $VERSION = '1.2';

# RFC does not required () to be encoded,
# however many engines do this so we want
# to match the output
our $URI_SAFE_CHARS = 'A-Za-z0-9\-_.!~*';

# Do not remove without verifing
# URI_SAFE_CHARS has been removed
# This is currently called from Branding modules

## ** If you update this module make sure you bring back %X to %x so we get lowercase
##

sub _uri_encode_str_fast {
    return defined $_[0] ? URI::XSEscape::uri_escape( $_[0] . '' ) : undef;    # force . ''  is to force pOK
}

sub _uri_decode_str_slow {
    return defined $_[0] ? ( ( ( $_[0] =~ tr<+>< >r ) =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/egr ) ) : ();
}

sub _uri_decode_str_fast {
    return defined $_[0] ? URI::XSEscape::uri_unescape( $_[0] =~ tr<+>< >r ) : ();
}

sub uri_decode_str_noform {
    return if !defined $_[0];
    return $_[0] =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/egr;
}

sub uri_encode_dirstr {
    return join( '/', ( map { uri_encode_str($_) } split( m{/}, shift ) ) );
}

1;
