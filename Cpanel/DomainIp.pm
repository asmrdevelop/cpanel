package Cpanel::DomainIp;

# cpanel - Cpanel/DomainIp.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Domain::Owner          ();
use Cpanel::Config::LoadCpUserFile ();

my %DOMAINIPCACHE;
my %OWNERIPCACHE;

our $VERSION = '1.6';

sub clear_domain_ip_cache {
    if (@_) {
        delete @DOMAINIPCACHE{@_};
    }
    else {
        %DOMAINIPCACHE = ();
        %OWNERIPCACHE  = ();
    }

    return;
}

sub getdomainip {
    my ( $domain, $no_cache ) = @_;
    return if !$domain;

    chomp $domain;
    $domain = lc $domain;

    substr( $domain, 0, 4, '' ) if rindex( $domain, 'www.', 0 ) == 0;

    if ( !$no_cache && exists $DOMAINIPCACHE{$domain} && $DOMAINIPCACHE{$domain} ) {
        return $DOMAINIPCACHE{$domain};
    }

    undef $DOMAINIPCACHE{$domain} if $no_cache;

    if ( !$DOMAINIPCACHE{$domain} ) {
        if ( my $owner = Cpanel::Domain::Owner::get_owner_or_undef($domain) ) {
            my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($owner);
            $OWNERIPCACHE{$owner} ||= $cpuser_ref->{'IP'};
            if ( ref $cpuser_ref->{'DOMAINS'} ) {    # nobody may not have a DOMAINS= line
                @DOMAINIPCACHE{ $cpuser_ref->{'DOMAIN'}, @{ $cpuser_ref->{'DOMAINS'} } } = ( $cpuser_ref->{'IP'} ) x ( 1 + scalar @{ $cpuser_ref->{'DOMAINS'} } );
            }
            elsif ( $cpuser_ref->{'DOMAIN'} ) {
                $DOMAINIPCACHE{ $cpuser_ref->{'DOMAIN'} } = $cpuser_ref->{'IP'};
            }
            return $OWNERIPCACHE{$owner} if $OWNERIPCACHE{$owner};
        }
    }
    return $DOMAINIPCACHE{$domain};
}

1;
