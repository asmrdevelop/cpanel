package Cpanel::StringFunc::Match;

# cpanel - Cpanel/StringFunc/Match.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

$Cpanel::StringFunc::Match::VERSION = '1.2';
use Cpanel::StringFunc::Case ();

sub beginmatch {

    #haystack = $_[0]
    #needle   = $_[1]
    return ( substr( $_[0], 0, length( $_[1] ) ) eq $_[1] ) ? 1 : 0;
}

sub ibeginmatch {
    return beginmatch( Cpanel::StringFunc::Case::ToLower( $_[0] ), Cpanel::StringFunc::Case::ToLower( $_[1] ) );
}

sub endmatch {

    #haystack = $_[0]
    #needle   = $_[1]
    return ( substr( $_[0], ( length( $_[1] ) * -1 ) ) eq $_[1] ) ? 1 : 0;
}

sub iendmatch {
    return endmatch( Cpanel::StringFunc::Case::ToLower( $_[0] ), Cpanel::StringFunc::Case::ToLower( $_[1] ) );
}

1;
