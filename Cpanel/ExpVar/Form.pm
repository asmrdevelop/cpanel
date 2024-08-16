package Cpanel::ExpVar::Form;

# cpanel - Cpanel/ExpVar/Form.pm                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

# use warnings not enabled in this module to preserve original behavior before refactoring

use Cpanel::Encoder::Tiny ();
use Cpanel::Encoder::URI  ();

# The behvaior of $cleanresult is very stronge, and prevents merging these expansions with the MultiPass expansions cleanly.

my %expansions = (
    FORM => sub {
        my $var         = shift;
        my $cleanresult = shift;

        my $result = defined $Cpanel::FORM{$var} ? $Cpanel::FORM{$var} : '';

        return ( $cleanresult ? Cpanel::Encoder::Tiny::safe_html_encode_str($result) : $result );
    },
    RAW_FORM => sub {
        my $var = shift;
        local $Cpanel::IxHash::Modify = 'none';
        return defined $Cpanel::FORM{$var} ? $Cpanel::FORM{$var} : '';
    },
    URI_ENCODED_FORM => sub {
        my $var = shift;
        local $Cpanel::IxHash::Modify = 'none';
        return Cpanel::Encoder::URI::uri_encode_str( defined $Cpanel::FORM{$var} ? $Cpanel::FORM{$var} : '' );
    },
);

sub has_expansion {    ##no critic qw(RequireArgUnpacking)
    return ( ref $_[0] && length $_[0]->{expansion} && ref $expansions{ $_[0]->{expansion} } && length $_[0]->{arg} );
}

sub expand {
    my $token           = shift;
    my $detaint_coderef = shift;
    my $cleanresult     = shift;

    if ( has_expansion($token) ) {
        if ( $Cpanel::CPVAR{'debug'} ) {
            print STDERR "Cpanel::ExpVar (DEBUG) Processing FORM var: $token->{arg}\n";
            print STDERR "Cpanel::ExpVar (DEBUG) Processed FORM var = " . ( defined $Cpanel::FORM{ $token->{arg} } ? $Cpanel::FORM{ $token->{arg} } : '' ) . "\n";
            if ($cleanresult) { print STDERR "Cpanel::ExpVar (DEBUG) fieldcleaner active\n"; }
        }
        my $expanded = $expansions{ $token->{expansion} }->( $token->{arg}, $cleanresult );
        $expanded = $detaint_coderef->($expanded) if defined $detaint_coderef;
        return $expanded . ( defined $token->{extra} ? $token->{extra} : '' );
    }
    else {
        # invalid expansion for this type
        return $token->{raw};
    }
}

1;
