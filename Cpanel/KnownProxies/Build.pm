package Cpanel::KnownProxies::Build;

# cpanel - Cpanel/KnownProxies/Build.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Debug            ();
use Cpanel::JSON             ();
use Cpanel::FileUtils::Write ();
use Cpanel::HTTP::Client     ();
use Cpanel::KnownProxies     ();
use Cpanel::SafeDir::MK      ();
use Cpanel::Validate::IP     ();
use Try::Tiny;

my %known_proxies = (
    'ipv4' => {
        'cloudflare' => { 'url' => 'https://www.cloudflare.com/ips-v4' },
    },
    'ipv6' => {
        'cloudflare' => { 'url' => 'https://www.cloudflare.com/ips-v6' },
    },
    'ipv6_that_forwards_to_ipv4_backend' => {

        # Cloudflare always forwards ipv6 to ipv4
        'cloudflare' => { 'url' => 'https://www.cloudflare.com/ips-v6' },
    },
);

our $TTL     = ( 86400 * 7 );    # 7 days
our $TIMEOUT = 30;

=encoding utf-8

=head1 NAME

Cpanel::KnownProxies::Build - Update the ip ranges of known proxies

=head1 SYNOPSIS

    # periodic background process
    use Cpanel::KnownProxies::Build;

    Cpanel::KnownProxies::Build::update();


    # A service
    use Cpanel::KnownProxies ();

    Cpanel::KnownProxies::reload();

    Cpanel::KnownProxies::is_known_proxy_ip('2.2.2.2');

=cut

=head2 update()

Updates the ip ranges of known proxies so Cpanel::KnownProxies::is_known_proxy_ip()
can determine if the passed ip is a known proxy.

=cut

sub update {
    Cpanel::SafeDir::MK::safemkdir( $Cpanel::KnownProxies::DYNAMIC_PROXIES, 0755 );

    my $ua  = Cpanel::HTTP::Client->new( 'timeout' => $TIMEOUT );
    my $now = time();
    foreach my $protocol ( keys %known_proxies ) {
        Cpanel::SafeDir::MK::safemkdir( "$Cpanel::KnownProxies::DYNAMIC_PROXIES/$protocol", 0755 );
        foreach my $provider ( keys %{ $known_proxies{$protocol} } ) {
            my $target_file = "$Cpanel::KnownProxies::DYNAMIC_PROXIES/$protocol/$provider.ranges.json";
            if ( ( ( stat($target_file) )[9] || 0 ) + $TTL <= $now ) {
                my $source_url = $known_proxies{$protocol}{$provider}{'url'};
                try {
                    my $response = $ua->get($source_url);

                    if ( $response->success() ) {
                        my @ips = split( m{\s+}, $response->content() );
                        my @valid_ips;
                        foreach my $ip (@ips) {
                            if ( Cpanel::Validate::IP::is_valid_ip_cidr_or_prefix($ip) ) {
                                push @valid_ips, $ip;
                            }
                            else {
                                Cpanel::Debug::log_warn("Invalid ip or range “$ip” seen in “$source_url”");
                            }
                        }

                        if (@valid_ips) {
                            Cpanel::FileUtils::Write::overwrite(
                                $target_file,
                                Cpanel::JSON::Dump( { 'ranges' => [ sort @valid_ips ] } ), 0644
                            );
                        }
                        else {
                            die "Failed to fetch ips from: “$source_url”: invalid content";
                        }
                    }
                    else {
                        die "Failed to fetch: “$source_url”: " . join( ' ', $response->status(), $response->reason() );
                    }

                }
                catch {
                    Cpanel::Debug::log_warn("Failed to update “$protocol” IPS for provider “$provider” because of an error: $_");
                };

            }
        }

    }
    return 1;
}
1;
