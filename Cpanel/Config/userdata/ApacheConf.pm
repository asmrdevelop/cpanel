package Cpanel::Config::userdata::ApacheConf;

# cpanel - Cpanel/Config/userdata/ApacheConf.pm    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#
#   This module is basically a re-implementation of Cpanel::Apacheconf, but
#   relying on the userdata cache as its data source, rather than httpd.conf.
#   Please use this module only for supporting legacy code that relied on
#   Cpanel::ApacheConf
#

use strict;

# find_include_deps may ask for
#
#   'use Cpanel ();'
#
# to be added, however it is only used if
# it is already loaded. Do not add
# it as it will bloat pkgacct
#
use Cpanel::Config::userdata::Cache ();
use Cpanel::Logger                  ();

my $logger = Cpanel::Logger->new();

#
#   This function is meant to be a replacement for Cpanel::ApacheConf::listsubdomains
#
sub listsubdomains {
    my ($user) = @_;

    $user ||= $Cpanel::user;

    my $cache = Cpanel::Config::userdata::Cache::load_cache($user);

    # $cache is a HASHREF
    # $cache keys are domains
    # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )

    #
    #   Build a hash with subdomains as keys, and docroots as values
    #   In the subdomain name, use an underscore instead of a dot
    #   to separate the subdomain prefix from the root domain (even if
    #   there are several levels of prefix, e.g. sub1.sub2.sub3_foo.com)
    #
    my %SUBDOMAINS = (
        map {    ## no critic qw(ControlStructures::ProhibitMutatingListFunctions)
            my $sub = $_;
            s/\./_/;    # only change the first . to a _
            $_ => $cache->{$sub}->[4]
          }
          grep { $cache->{$_}->[2] eq 'sub' }
          keys %$cache
    );

    return wantarray ? %SUBDOMAINS : \%SUBDOMAINS;
}

sub getparked {
    my ( $domain, $user ) = @_;

    $user ||= $Cpanel::user;
    my $cache = Cpanel::Config::userdata::Cache::load_cache($user);

    # $cache is a HASHREF
    # $cache keys are domains
    # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )

    my %parked = (
        map    { $_ => $cache->{$_}->[4] }
          grep { $cache->{$_}->[3] eq $domain && ( $cache->{$_}->[2] eq 'parked' || $cache->{$_}->[2] eq 'addon' ) }
          keys %$cache
    );

    return wantarray ? %parked : \%parked;
}

sub getmultiparked {
    my %parent_list = map { $_ => 1 } @_;
    my %multiparked;

    my $cache = Cpanel::Config::userdata::Cache::load_cache();
    for my $dns_name ( keys %{$cache} ) {
        my ( $type, $parent, $docroot ) = ( @{ $cache->{$dns_name} } )[ 2, 3, 4 ];
        next unless ( $parent_list{$parent} );
        next unless ( $type eq 'parked' || $type eq 'addon' );
        $multiparked{$parent}{$dns_name} = $docroot;
    }

    return wantarray ? %multiparked : \%multiparked;
}

sub getaddon {
    my ($user) = @_;

    my $cache = Cpanel::Config::userdata::Cache::load_cache($user);

    # $cache is a HASHREF
    # $cache keys are domains
    # $cache values are a ARRAYREF with ( 0 $owner, 1 $reseller, 2 $type, 3 $parent, 4 $docroot )

    my %addon;
    for my $domain ( keys %$cache ) {
        next unless $cache->{$domain}->[2] eq 'addon' && $cache->{$domain}->[0] eq $user;
        $addon{ $cache->{$domain}->[3] }{$domain} = $cache->{$domain}->[4];
    }

    return wantarray ? %addon : \%addon;
}

sub _rootdomains {
    my @domains    = @_;
    my %domain_map = map { $_ => 1 } @domains;
    delete $domain_map{''};    #jic

    foreach my $domain ( keys %domain_map ) {
        my @domain_parts = split /\./, $domain;
        while ( shift @domain_parts && @domain_parts >= 2 ) {
            if ( $domain_map{ join '.', @domain_parts } ) {
                delete $domain_map{$domain};
                last;
            }
        }
    }
    my @root_domains = ( keys %domain_map );

    return wantarray ? @root_domains : \@root_domains;
}

sub getdirindices {
    require Cpanel::EA4::Conf;

    my @indices = split(
        /\s+/,
        Cpanel::EA4::Conf->instance()->directoryindex(),
    );

    return (@indices);
}

1;
