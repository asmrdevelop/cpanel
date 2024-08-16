package Cpanel::DomainLookup;

# cpanel - Cpanel/DomainLookup.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

#use Cpanel                          ();
# Cpanel will already be included if needed
# do not include for memory
use Cpanel::Config::userdata::Load  ();
use Cpanel::Config::userdata::Cache ();
use Cpanel::PwCache                 ();

my ( $SubDomains, $MULTIPARKED, %domainCache );

#used from tests
sub reset_caches {
    %domainCache = ();
    undef $SubDomains;
    undef $MULTIPARKED;
    Cpanel::DomainLookup::DocRoot::_reset_caches() if $INC{'Cpanel/DomainLookup/DocRoot.pm'};
    return;
}

my $PERMIT_MEMORY_CACHE = 1;

our $VERSION = '1.2';

sub DomainLookup_init { }

#
# These are domain that will have dns zones
#
sub api2_getbasedomains {
    if ( exists $domainCache{'basedomains'} ) {
        return [ map { { 'domain' => $_ } } sort keys %{ $domainCache{'basedomains'} } ];
    }

    my $ud    = Cpanel::Config::userdata::Load::load_userdata_main( Cpanel::PwCache::getusername() );
    my @DLIST = ( $ud->{'main_domain'} );

    if ( !$MULTIPARKED ) {
        getmultiparked();
    }

    foreach my $park_root ( keys %$MULTIPARKED ) {
        push @DLIST, keys %{ $MULTIPARKED->{$park_root} };
    }

    push @DLIST, _getadditionaldomains();

    my %UNIQ_DOMAINS;
    @UNIQ_DOMAINS{@DLIST} = ();
    $domainCache{'basedomains'} = \%UNIQ_DOMAINS;

    my @RSD = map { { 'domain' => $_ } } sort keys %UNIQ_DOMAINS;
    $Cpanel::CPVAR{'basedomainscount'} = scalar @RSD;    # PPI NO PARSE - only need to set if already loaded

    return \@RSD;
}

sub api2_countbasedomains {
    return [ { 'count' => scalar @{ api2_getbasedomains() } } ];
}

sub listsubdomains {
    if ( !$SubDomains ) {
        my $cache = Cpanel::Config::userdata::Cache::load_cache( Cpanel::PwCache::getusername(), $PERMIT_MEMORY_CACHE );

        # $cache is a HASHREF
        # $cache keys are domains
        # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )
        if ( $cache && ref $cache eq 'HASH' ) {
            my $rootregex = join '|', map { quotemeta } grep { $cache->{$_}->[2] ne 'sub' } keys %$cache;

            # same as s/\.$DOMAIN/_$DOMAIN/
            $SubDomains = { map { ( $_ =~ s/\.(?=(?:${rootregex})$)/_/r ) => $cache->{$_}->[4] } grep { $cache->{$_}->[2] eq 'sub' } keys %$cache };
        }
        else {
            $SubDomains = {};
        }
    }
    return %$SubDomains;
}

# These domains are the ones root or a reseller assigns us through WHM.
# For legacy reasons (?), this is tested directly.
sub _getadditionaldomains {
    my %domains = map { $_ => 1 } @Cpanel::DOMAINS;
    my $cache   = Cpanel::Config::userdata::Cache::load_cache( Cpanel::PwCache::getusername(), $PERMIT_MEMORY_CACHE );

    # $cache keys are domains
    if ( $cache && %$cache ) {
        for my $domain ( keys %$cache ) {
            delete $domains{$domain};
        }
    }
    return keys %domains;
}

sub flushmultiparked {
    $MULTIPARKED = undef;
    Cpanel::Config::userdata::Cache::reset_cache();
    return;
}

sub getmultiparked {
    if ( !$MULTIPARKED ) {
        $MULTIPARKED = {};
        my $cache = Cpanel::Config::userdata::Cache::load_cache( Cpanel::PwCache::getusername(), $PERMIT_MEMORY_CACHE );

        # $cache is a HASHREF
        # $cache keys are domains
        # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )
        if ( $cache && %$cache ) {
            for my $domain ( grep { $cache->{$_}->[2] eq 'parked' || $cache->{$_}->[2] eq 'addon' } keys %$cache ) {
                $MULTIPARKED->{ $cache->{$domain}->[3] }->{$domain} = $cache->{$domain}->[4];
            }
        }
    }
    return %$MULTIPARKED;
}

sub getparked {
    my ($mydomain) = @_;
    if ( !$MULTIPARKED ) {
        getmultiparked();
    }
    if ( exists $MULTIPARKED->{$mydomain} ) {
        return %{ $MULTIPARKED->{$mydomain} };
    }
    return ();
}

## note usage from ::Mime; best to check for local ownership of $domain before
##   calling this; the logic gets faulty for wildcard domains and external domains
#
#XXX XXX XXX: This will ALWAYS return something!! Do NOT depend on it to tell you
#whether a given domain actually has a docroot. Ignore any messages of success.
#This can only lead to FAILURE.
#
sub getdocroot {
    my $domain = shift;
    my $docroot;

    $domain = lc $domain if defined $domain;

    my $user = Cpanel::PwCache::getusername();
    my $ud   = Cpanel::Config::userdata::Load::load_userdata( $user, $domain );
    if ( $ud && keys %$ud ) {
        $docroot = $ud->{'documentroot'};
    }
    else {
        if ( !$MULTIPARKED ) {
            getmultiparked();
        }
        for my $sub_domain ( keys %$MULTIPARKED ) {
            if ( exists $MULTIPARKED->{$sub_domain}->{$domain} ) {
                $docroot = $MULTIPARKED->{$sub_domain}->{$domain};
                last;
            }
        }
    }

    my $homedir = $Cpanel::homedir || Cpanel::PwCache::gethomedir();    # PPI NO PARSE - gethomedir() called if no initcp

    if ( !$docroot ) {
        $docroot = $homedir . '/public_html';
    }
    if (wantarray) {
        ( my $reldocroot = $docroot ) =~ s{^$homedir/}{};
        return ( $docroot, $reldocroot );
    }
    return $docroot;
}

sub getdocrootlist {
    my $user     = shift;    # optional
    my %DOCROOTS = ();
    require Cpanel::DomainLookup::DocRoot;
    my $docroots_ref = Cpanel::DomainLookup::DocRoot::getdocroots($user);
    foreach my $domain ( keys %{$docroots_ref} ) {
        $DOCROOTS{ $docroots_ref->{$domain} } = 1;
    }
    return \%DOCROOTS;
}

sub api2_getdocroots {
    require Cpanel::DomainLookup::DocRoot;
    my $docroots = Cpanel::DomainLookup::DocRoot::getdocroots();
    return [ map { { 'domain' => $_, 'docroot' => $docroots->{$_} } } sort keys %{$docroots} ];
}

sub api2_getdocroot {
    my %OPTS   = @_;
    my $domain = $OPTS{'domain'};

    my ( $docroot, $reldocroot ) = getdocroot($domain);
    return [ { 'docroot' => $docroot, 'reldocroot' => $reldocroot } ];
}

sub api2_getmaindomain {
    my $ud = Cpanel::Config::userdata::Load::load_userdata_main( Cpanel::PwCache::getusername() );
    return [ { 'main_domain' => $ud->{'main_domain'} } ];
}

## note: current only known caller is ::Mime
sub resolve_url_to_localpath {
    my $url = shift;
    $url =~ s/^\s*//g;
    my $username = Cpanel::PwCache::getusername();
    if ( $url !~ /^[^\:]+\:\/\// ) {    ## if $url does not have the ^protocol://
        my $ud = Cpanel::Config::userdata::Load::load_userdata_main($username);
        $url = 'http://' . $ud->{'main_domain'} . '/' . $url;
    }

    ## separate protocol, domain, and the rest
    $url =~ m<^([^:]+)://([^/]+)(.*)> or do {
        die "“$url” doesn’t look like a URI!";
    };

    my ( $protocol, $host, $uri ) = ( $1, $2, $3 );

    $uri =~ tr{/}{}s;                   # collapse //s to /
    $uri =~ s{/$}{}g;                   # strip trailing slash

    ## note: the only known caller already does the wildcard check,
    ##   but just in case there is another caller out there
    my $is_wildcard = ( $host eq '.*' || $host eq '(.*)' );

    if ( !$is_wildcard ) {
        my $user_owns_domain = do {
            require Cpanel::Domain::Authz;
            Cpanel::Domain::Authz::user_controls_domain( $username, $host );
        };

        if ( !$user_owns_domain ) {
            return ( 0, '' );
        }
    }

    my $docroot = ( getdocroot($host) )[0];
    if ( !$docroot ) {
        return ( 0, '' );
    }
    my $localpath = $docroot . $uri;
    $localpath =~ tr{/}{}s;    # collapse //s to /
    return ( 1, $localpath, $protocol );
}

my $allow_demo = { allow_demo => 1 };

our %API = (
    getdocroot       => $allow_demo,
    getdocroots      => $allow_demo,
    getbasedomains   => $allow_demo,
    getmaindomain    => $allow_demo,
    countbasedomains => $allow_demo,
);

sub api2 {
    my ($func) = @_;
    return { %{ $API{$func} } } if $API{$func};
    return;
}

1;
