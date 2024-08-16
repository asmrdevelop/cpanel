package Cpanel::CheckData;

# cpanel - Cpanel/CheckData.pm                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

# TODO: return; instead of return 0; if useage (SSL.pm) allows it/can easily be made to allow for it

sub isvalidemail {
    my ($addr) = @_;

    return 0 unless defined $addr;

    my ( $name, $domain ) = split( /\@/, $addr, 2 );
    require Cpanel::Validate::Domain::Tiny;
    return 0 if !Cpanel::Validate::Domain::Tiny::validdomainname($domain);

    ## RFC 2822 3.2.4 && atext: atom or dot-atom
    ## 3.4.1: contains a locally interpreted string followed by the at-sign
    ## ... The locally interpreted string is either a quoted-string or a dot-atom
    # my $rfc2822_atom = quotemeta("a-z0-9!#$%&'*+-/=?^_`{|}~");
    ## dot-atom:  atom.atom
    # return if $name !~ m/^$rfc2822_atom(:?[.]$rfc2822_atom)*$/i; # && $name !~ $rfc2822_quoted_string

    # m/^[^\@]+\@[^\.]+\.\S+/
    # [\w][\w\-\.\+\%]*\@[\w][\w\-\.]*\.[a-z]+
    # ^[\w][\w\-\.\+\%]*$
    # ^[a-z0-9][a-z0-9\_\-\.\+\%]*[a-z0-9]$
    return 0 if $name !~ m/^[^\@\s]+$/;    # rudimentary check only
    return 1;
}

sub is_empty_or_valid_email {
    my ($str) = @_;
    return 1 if !defined $str || $str eq '' || isvalidemail($str);
    return 0;
}

1;
