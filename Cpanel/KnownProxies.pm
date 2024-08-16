package Cpanel::KnownProxies;

# cpanel - Cpanel/KnownProxies.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::JSON            ();
use Cpanel::ArrayFunc::Uniq ();
use Cpanel::IP::Match       ();
use Cpanel::SafeDir::Read   ();
use Try::Tiny;

my %ranges;

our $DIST_PROXIES    = '/usr/local/cpanel/3rdparty/share/knownproxies';
our $DYNAMIC_PROXIES = '/var/cpanel/etc/knownproxies';

=encoding utf-8

=head1 NAME

Cpanel::KnownProxies - Tool for checking to see if an ip is a known proxy

=head1 SYNOPSIS

    use Cpanel::KnownProxies ();

    Cpanel::KnownProxies::reload();

    if ( Cpanel::KnownProxies::is_known_proxy_ip('2.2.2.2') ) {
        # semi-trust the ip in the X-Proxy.. field
    }

=cut

=head2 reload()

Reloads the known proxy ip ranges from disk.  This must be
called at least once before is_known_proxy_ip()

=cut

sub reload {
    foreach my $type (qw(ipv4 ipv6 ipv6_that_forwards_to_ipv4_backend)) {
        foreach my $dir ( "$DIST_PROXIES/$type", "$DYNAMIC_PROXIES/$type" ) {
            foreach my $list ( Cpanel::SafeDir::Read::read_dir($dir) ) {
                try {
                    my $ref = Cpanel::JSON::LoadFile("$dir/$list");
                    push @{ $ranges{$type} }, @{ $ref->{'ranges'} };
                }
                catch {
                    warn;

                };
            }
        }
        @{ $ranges{$type} } = Cpanel::ArrayFunc::Uniq::uniq( @{ $ranges{$type} } );
    }

    return 1;
}

=head2 is_known_proxy_ip($ip)

Returns true if the given IP address is in a known proxy range.

Returns false if the given IP address is NOT in a known proxy range.

This can handle both IPv4 and IPv6 addresses.

=cut

sub is_known_proxy_ip {
    return _match_knownproxy_ip( $_[0] =~ tr{:}{} ? 'ipv6' : 'ipv4', $_[0] );
}

=head2 is_known_proxy_ipv6_that_forwards_to_ipv4_backend($ipv4)

Returns true if the given IP address is in a known proxy range that forwards ipv6 to ipv4.

Returns false if the given IP address is NOT in a known proxy range that forwards ipv6 to ipv4.

This can handle IPv6 addresses only.

=cut

sub is_known_proxy_ipv6_that_forwards_to_ipv4_backend {
    return _match_knownproxy_ip( 'ipv6_that_forwards_to_ipv4_backend', $_[0] );
}

sub _match_knownproxy_ip {
    die 'Need IPv6 or IPv4 address!' if !$_[1];
    die 'Must call reload() first!'  if !%ranges;

    #Avoid auto-vivifying the array reference if it doesn’t exist.
    if ( $ranges{ $_[0] } ) {
        foreach my $range ( @{ $ranges{ $_[0] } } ) {
            return 1 if Cpanel::IP::Match::ip_is_in_range( $_[1], $range );
        }
    }

    return 0;
}

1;
