package Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils;

# cpanel - Cpanel/ApacheConf/ModRewrite/RewriteCond/Utils.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=encoding utf-8

=head1 NAME

Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils

=head1 SYNOPSIS

    use Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils ();

    #Handles regexp, string, and numeric comparisons as described
    #in the documentation for RewriteCond.
    #Also safeguards against Perl’s weird handling of m<>.
    my $yn = Cpanel::ApacheConf::ModRewrite::RewriteCond::Utils::pattern_matches(
        '^haha',
        'This won’t match.',
        'nocase',   #optional
    );

=cut

use strict;
use warnings;

use Try::Tiny;

use Cpanel::ApacheConf::ModRewrite::Utils ();
use Cpanel::Exception                     ();

sub pattern_matches {
    my ( $pattern, $test_value, @attrs ) = @_;

    my $nocase = grep { $_ eq 'nocase' } @attrs;

    my ($negated) = ( $pattern =~ s<\A(!)><> );

    my $ret;

    if ( my ( $strcmp_type, $str ) = $pattern =~ m/\A([><]=?|=)(.*)/ ) {
        if ($nocase) {
            tr<A-Z><a-z> for ( $test_value, $str );
        }

        if ( $strcmp_type eq '<' ) {
            $ret = $test_value lt $str;
        }
        elsif ( $strcmp_type eq '<=' ) {
            $ret = $test_value le $str;
        }
        elsif ( $strcmp_type eq '>' ) {
            $ret = $test_value gt $str;
        }
        elsif ( $strcmp_type eq '>=' ) {
            $ret = $test_value ge $str;
        }
        elsif ( $strcmp_type eq '=' ) {
            $ret = $test_value eq $str;
        }
        else {    #shouldn’t ever happen, but just in case
            die "Unrecognized string comparison type: “$negated$pattern”!";
        }
    }

    #Numeric comparisons
    elsif ( my ( $numcmp_type, $num ) = $pattern =~ m<\A-(eq|ne|[gl][et])(.*)\z> ) {
        if ( $numcmp_type eq 'eq' ) {
            $ret = $test_value == $num;
        }
        elsif ( $numcmp_type eq 'ne' ) {
            $ret = $test_value != $num;
        }
        elsif ( $numcmp_type eq 'lt' ) {
            $ret = $test_value < $num;
        }
        elsif ( $numcmp_type eq 'le' ) {
            $ret = $test_value <= $num;
        }
        elsif ( $numcmp_type eq 'gt' ) {
            $ret = $test_value > $num;
        }
        elsif ( $numcmp_type eq 'ge' ) {
            $ret = $test_value >= $num;
        }
        else {    #shouldn’t ever happen, but just in case
            die "Unrecognized numeric comparison type: “$negated$pattern”!";
        }
    }
    elsif ( my ($fstest_type) = $pattern =~ m<\A-([dfFhlLsUx])\z> ) {
        die Cpanel::Exception::create( 'Unsupported', '“[_1]” does not support filesystem checks.', [__PACKAGE__] );
    }
    else {
        $ret = Cpanel::ApacheConf::ModRewrite::Utils::regexp_str_match(
            $pattern,
            $test_value,
            ( $nocase ? 'nocase' : () ),
        );
    }

    $ret = !$ret if $negated;

    return $ret ? 1 : 0;
}

1;
