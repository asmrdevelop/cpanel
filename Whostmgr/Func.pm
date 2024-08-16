package Whostmgr::Func;

# cpanel - Whostmgr/Func.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Whostmgr::Math ();

*is_subdomain_of_domain = *is_true_subdomain_of_domain;

# unlimitedint is a slightly confusing name because this function
# does not in fact truncate values to their integer portion. However,
# you can make it do this using the optional $num_modifier parameter,
# which adjusts the return value conditioned on the fact that it is
# actually a number. Don't forget to say "int shift" instead of just
# "int" or "int $_".
# Example usage: unlimitedint( $somevalue, sub { int shift } );
# Alt Example (Convert MB to Bytes or Unlimited): unlimitedint( $somevalue, sub { int shift * 1024 * 1024 } );
sub unlimitedint {
    my ( $value, $num_modifier ) = @_;
    if ( !defined $value || $value eq '' || $value =~ m/unlim/i ) {
        return 'unlimited';
    }
    else {
        my $num = Whostmgr::Math::unsci($value);
        if ($num_modifier) {
            my $modified = Whostmgr::Math::unsci( &$num_modifier($num) );
            require Carp;
            Carp::croak("bad num modifier") if not defined $modified;    # misuse could cause subtle bugs, so catch them
            return $modified;
        }
        return $num;
    }
}

sub noint {
    if ( !defined( $_[0] ) || $_[0] eq 'n' || $_[0] eq '' ) {
        return 'n';
    }
    return Whostmgr::Math::unsci( $_[0] );
}

sub yesno {
    my $value = shift;
    if ( defined $value && $value =~ m/^\s*([yn])\s*$/i ) {
        return lc $1;
    }
    elsif ($value) {
        return 'y';
    }
    return 'n';
}

sub is_true_subdomain_of_domain {

    #ex is_true_subdomain_of_domain('pig.cow.org','cow.org') == true
    my $testdomain = shift;
    my $domain     = shift;

    my @domain_parts     = split( /\./, $domain );
    my @testdomain_parts = split( /\./, $testdomain );

    # get rid of ccTLDs
    if ( length( $domain_parts[-1] ) == 2 && $domain_parts[-1] eq $testdomain_parts[-1] ) {
        pop @domain_parts;
        pop @testdomain_parts;
    }

    my $num_of_elements = scalar @domain_parts;

    foreach my $index ( reverse 0 .. $#domain_parts ) {
        if ( @testdomain_parts && $domain_parts[$index] eq $testdomain_parts[-1] ) {
            pop @domain_parts;
            pop @testdomain_parts;
        }
        else {
            last;
        }
    }

    # If domain was not a FQDN and they matched, then testdomain must be a sub of domain
    if ( !scalar @domain_parts ) {
        return 1;
    }

    # Didn't match any
    if ( $num_of_elements == scalar @domain_parts ) {
        return 0;
    }

    # Both contain more than one element, must not be a sub
    if ( scalar @domain_parts > 1 && scalar @testdomain_parts > 1 ) {
        return 0;
    }

    return 0;
}

1;
