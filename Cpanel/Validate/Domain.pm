package Cpanel::Validate::Domain;

# cpanel - Cpanel/Validate/Domain.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.0';

use Cpanel::Exception              ();
use Cpanel::Sys::Hostname          ();
use Cpanel::Validate::Domain::Tiny ();

sub valid_wild_domainname {
    my ( $domain, $quiet ) = @_;
    return Cpanel::Validate::Domain::Tiny::validdomainname( $domain, $quiet ) unless index( $domain, '*.' ) > -1;

    # Skip the wildcard.
    return Cpanel::Validate::Domain::Tiny::validdomainname( substr( $domain, 2 ), $quiet );
}

# This function enforces RFC 1035’s validation.
#
# Note that DNS nowadays only imposes length restrictions on labels,
# which is much more relaxed than RFC 1035.
# See: https://tools.ietf.org/html/rfc2181#section-11
#
sub valid_rfc_domainname_or_die {
    my ($domain) = @_;

    return _valid_or_die( $domain, \&Cpanel::Validate::Domain::Tiny::validdomainname );
}

sub valid_wild_domainname_or_die {
    my ($domain) = @_;

    return _valid_or_die( $domain, \&valid_wild_domainname );
}

sub valid_domainname_for_customer_or_die {
    my ($domain) = @_;

    if ( !is_valid_cpanel_domain( $domain, my $why ) ) {
        die Cpanel::Exception::create( 'DomainNameNotAllowed', [ given => $domain, why => $why ] );
    }

    return 1;
}

sub is_cpanel_only_domain {
    return
         $_[0] eq 'cpanel.net'
      || $_[0] eq 'cpanel.com'
      || $_[0] =~ m/\.(?:cpanel\.(?:net|com))\z/i;
}

sub is_disallowed_domain {
    return
         $_[0] eq 'ruby-on-rails.db'
      || $_[0] eq 'ruby-on-rails-rewrites.db'
      || $_[0] eq 'ftpxferlog.offsetftpsep';
}

sub has_disallowed_tld {
    return $_[0] =~ m/\.(?:bkup2?|cache|json|lock|mbox|offset|stor|yaml|invalid|localhost)\z/i;
}

#This is like Cpanel::Validate::Domain::Tiny::validdomainname, but it also verifies that:
#   - the TLD is valid
#   - the domain is not propriety of cPanel, L.L.C.
#
#(i.e., that the domain is valid for a cPanel customer to use)
#
# Note that domain normalization, if performed, must occur before calling this
# function.
#
#Arguments are:
#   - the string to validate
#   - (optional) a scalar into which to put the "why"
#
#NOTE: This function is always "quiet".
#
sub is_valid_cpanel_domain {    ##no critic qw(RequireArgUnpacking)
                                # $_[0]: domain
                                # $_[1]: message
    my $domain = $_[0];

    my $quiet = 1;
    my ( $result, $reason ) = Cpanel::Validate::Domain::Tiny::validdomainname( $domain, $quiet );

    if ($result) {
        if ( has_disallowed_tld($domain) ) {
            undef $result;
            $reason = $domain . ' domain name has a disallowed TLD label';
        }

        if ( is_disallowed_domain($domain) ) {
            undef $result;
            $reason = $domain . ' is a disallowed domain';
        }

        my $hostname = Cpanel::Sys::Hostname::gethostname();

        if ( is_cpanel_only_domain($domain) && ( $hostname !~ m/\.cpanel\.net$/ ) ) {
            undef $result;
            $reason = $domain . ' is a cPanel domain';
        }

        if ( rindex( $domain, 'www.', 0 ) == 0 ) {
            undef $result;
            $reason = $domain . ' starts with “www.”, which is not allowed';
        }
    }

    # Assign the reason directly into the second scalar passed into this subroutine.
    if ( scalar @_ >= 2 ) {
        $_[1] = $reason;
    }

    return $result;
}

#
#  Note: while *.*.domain.com and *cow.domain.com are technically
#  valid, IE and FireFox reject them.   As such we treat them as invalid
#
sub validwildcarddomain {
    my ($domainname) = @_;

    return Cpanel::Validate::Domain::Tiny::validdomainname($domainname) if index( $domainname, '*' ) == -1;

    if ( is_valid_wildcard_domain($domainname) ) {
        $domainname =~ tr{*}{a};    #replace * with a for Cpanel::Validate::Domain::Tiny::validdomainname to understand this
        return Cpanel::Validate::Domain::Tiny::validdomainname($domainname);
    }
    else {
        return wantarray ? ( 0, "domain name is not a valid wildcard format" ) : 0;
    }
}

sub is_valid_wildcard_domain {
    my ($domain) = @_;

    if ( $domain =~ /.\*/ ) {
        return 0;
    }
    elsif ( $domain =~ /\*[^\.]/ ) {
        return 0;
    }

    return 1;
}

#----------------------------------------------------------------------

sub _valid_or_die {
    my ( $domain, $tester_cr ) = @_;

    my ( $ok, $why ) = $tester_cr->( $domain, 1 );    #1 to make it not log->warn

    if ( !$ok ) {

        #This is *technically* not right since wildcard domains themselves are never RFC-compliant.
        #If that's ever an issue, rethink this exception type.
        die Cpanel::Exception::create( 'DomainNameNotRfcCompliant', [ given => $domain, why => $why ] );
    }

    return 1;
}

1;
