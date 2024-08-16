package Cpanel::Validate::SubDomain;

# cpanel - Cpanel/Validate/SubDomain.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#use warnings; #not for production -- passes
#use strict;  #not for production  -- passes

use Cpanel::StringFunc::Case ();
use Cpanel::StringFunc::Trim ();

#This regex must be valid in JavaScript as well as in Perl.
our $REGEX = q{^\*$|^(?:\*\.)?[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?(?:\.[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?)*$};

our %RESERVED_SUBDOMAINS = ( 'www' => 1, '_wildcard_' => 1, 'wildcard_safe' => 1 );

sub is_valid {
    my ($subdom) = @_;
    return $subdom =~ /\A\*\z|\A(?:\*\.)?[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?(?:\.[\da-zA-Z](?:[-\da-zA-Z]*[\da-zA-Z])?)*\z/ ? 1 : ();
}

sub normalize {
    my ($subdom) = @_;

    $subdom = Cpanel::StringFunc::Case::ToLower( Cpanel::StringFunc::Trim::ws_trim($subdom) );

    return $subdom;
}

sub is_reserved {
    my $domain = shift;

    $domain = &normalize($domain);

    if ( $RESERVED_SUBDOMAINS{$domain} ) {
        return 1;
    }

    foreach my $regex ( keys %RESERVED_SUBDOMAINS ) {
        if ( $domain =~ /^\Q$regex\E\./i ) {
            return 1;
        }
    }

    return 0;
}

sub list_reserved {
    return wantarray ? keys %RESERVED_SUBDOMAINS : [ keys %RESERVED_SUBDOMAINS ];
}

1;    # Magic true value required at end of module
