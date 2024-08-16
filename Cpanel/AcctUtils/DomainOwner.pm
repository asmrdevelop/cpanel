package Cpanel::AcctUtils::DomainOwner;

# cpanel - Cpanel/AcctUtils/DomainOwner.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=head1 NAME

Cpanel::AcctUtils::DomainOwner

=cut

use strict;
use warnings;

use Cpanel::AcctUtils::DomainOwner::Tiny ();
use Cpanel::Reseller                     ();
use Cpanel::AcctUtils::Owner             ();
use Cpanel::FileLookup                   ();
use Cpanel::LocaleString                 ();

*getdomainowner = *Cpanel::AcctUtils::DomainOwner::Tiny::getdomainowner;

sub check_each_domain_level_for_ownership {
    my ( $user, $domain ) = @_;

    substr( $domain, 0, 4, '' ) if rindex( $domain, 'www.', 0 ) == 0;
    $domain =~ tr{/}{}d;

    # Do not build the cache here as it will produce inconsistent results
    # and likely is not needed anyways since getdomainowner is now faster

    my @DNSPATH    = split( /\./, $domain );
    my @SEARCHPATH = pop(@DNSPATH);
    my $user_is_reseller;

    while ( scalar @DNSPATH > 0 ) {
        unshift( @SEARCHPATH, pop(@DNSPATH) );
        my $searchdomain = join( '.', @SEARCHPATH );
        if ( my $rootdomainowner = getdomainowner( $searchdomain, { 'default' => '', 'skiptruelookup' => 1 } ) ) {
            if ( $rootdomainowner ne $user ) {

                # If the user is a reseller we need to check to see if
                # the rootdomainowner is owned by them
                if ( !defined $user_is_reseller ) {
                    $user_is_reseller = Cpanel::Reseller::isreseller($user);
                }
                if ( !$user_is_reseller || Cpanel::AcctUtils::Owner::getowner($rootdomainowner) ne $user ) {
                    return ( 0, $searchdomain, $rootdomainowner );
                }
            }
        }
        elsif ( _zone_exists($searchdomain) ) {
            return ( 0, $searchdomain );
        }
    }

    return 1;
}

sub _zone_exists {
    my ($zone) = @_;
    if ( !$INC{'Cpanel/DnsUtils/AskDnsAdmin.pm'} ) {
        local $@;
        eval 'require Cpanel::DnsUtils::AskDnsAdmin;';
        if ($@) { die "Failed to load Cpanel::DnsUtils::AskDnsAdmin: $@" }
    }
    return 'Cpanel::DnsUtils::AskDnsAdmin'->can('askdnsadmin')->( 'ZONEEXISTS', $Cpanel::DnsUtils::AskDnsAdmin::REMOTE_AND_LOCAL, $zone );
}

my $locale;

sub _croak_maketext {    ## no extract maketext
    my ($str) = @_;

    # Only loaded when required
    local $@;
    eval 'require Cpanel::Locale; require Cpanel::Carp;';    ## no critic qw(ProhibitStringyEval) -- quoted eval to hide this from perlcc
    if ($@) { die "Failed to load Cpanel::Locale or Cpanel::Carp: $@"; }
    $locale ||= 'Cpanel::Locale'->get_handle();
    die 'Cpanel::Carp'->can('safe_longmess')->( $str->to_string() );
}

=head2 is_domain_owned_by

Who is the domain owned by?

=head3 Arguments

- $domain - String - The domain to check ownership

- $user - String - The user who might or might not own the domain. This may
be either a username or a numeric uid.

=head3 Returns

This function returns a boolean value indicating whether the specified user
owns the domain in question.

Domains that don't exist are treated the same as existing domains that are not
owned by the user.

=head3 Throws

If the specified user is nonexistent, or a problem occurs during the lookup,
this function will throw an exception. Callers must either catch and handle
the exception or be willing to have execution end in such a case.

=cut

sub is_domain_owned_by {
    my ( $domain, $user ) = @_;

    if ( !length $domain ) {
        _croak_maketext(    ## no extract maketext
            Cpanel::LocaleString->new('The domain ownership check failed because the caller did not specify a domain.')
        );
    }
    if ( !length $user ) {
        _croak_maketext(    ## no extract maketext
            Cpanel::LocaleString->new('The domain ownership check failed because the caller did not specify a username or [asis,UID].')
        );
    }

    # Convert uid to username
    if ( $user !~ tr{0-9}{}c ) {    # contains only numerals
        local $@;
        eval 'require Cpanel::PwCache;';    ## no critic qw(ProhibitStringyEval) -- quoted eval to hide this from perlcc
        if ($@) { die "Failed to load Cpanel::PwCache: $@" }
        $user = ( 'Cpanel::PwCache'->can('getpwuid')->( int $user ) )[0];
        if ( !length $user ) {
            _croak_maketext(                ## no extract maketext
                Cpanel::LocaleString->new('The domain ownership check failed because the system could not convert the [asis,UID] into a username.')
            );
        }
    }

    my $domainowner = getdomainowner( $domain, { default => '' } );

    return 1 if $domainowner eq $user;
    return 0;
}

sub gettruedomainowner {
    my $domain = shift;
    my $opref  = shift;
    my $name   = Cpanel::FileLookup::filelookup( '/etc/trueuserdomains', 'key' => $domain );
    if ( !$name ) {

        #defined because we may want ''
        if ( defined $opref->{'default'} ) { return $opref->{'default'}; }
        return 'root';
    }
    else {
        return $name;
    }
}

1;
