package Cpanel::StringFunc::UnquoteMeta;

# cpanel - Cpanel/StringFunc/UnquoteMeta.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#Reduces double-backslash to one backslash, and removes single backslash.
sub unquotemeta {
    my ($string) = @_;
    return ''                 if !defined $string;              # quotemeta() undef behavior
    $string =~ s/\\(\\|)/$1/g if index( $string, '\\' ) > -1;
    return $string;
}

1;
