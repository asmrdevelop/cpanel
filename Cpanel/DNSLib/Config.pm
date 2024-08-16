package Cpanel::DNSLib::Config;

# cpanel - Cpanel/DNSLib/Config.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
## no critic qw(TestingAndDebugging::RequireUseWarnings)
#
use Cpanel::DNSLib::PeerConfig   ();
use Cpanel::AdminBin::Serializer ();
use Cpanel::FileUtils::Write     ();

use constant _ENOENT => 2;

our $VERSION = $Cpanel::DNSLib::PeerConfig::VERSION;

*getdnspeers    = \&Cpanel::DNSLib::PeerConfig::getdnspeers;
*getdnspeerlist = \&Cpanel::DNSLib::PeerConfig::getdnspeerlist;

our $DEFAULT_AUTODISABLE_THRESHOLD = 10;

sub getclusteruserpass {
    my $config_ref = get_cluster_member_config(@_);

    return @{$config_ref}{qw(host user pass dnsrole)};
}

sub get_cluster_member_config {
    my ( $clustermaster, $cluster_user ) = @_;

    if ( !$cluster_user ) { $cluster_user = $ENV{'REMOTE_USER'} || 'root'; }
    $cluster_user  =~ s/\.\.//g;
    $clustermaster =~ s/\.\.//g;
    $cluster_user  =~ tr{/}{}d;
    $clustermaster =~ tr{/}{}d;

    if ( !-e '/var/cpanel/cluster/' . $cluster_user . '/config/' . $clustermaster ) {
        if ( -e '/var/cpanel/cluster/root/config/' . $clustermaster ) {
            $cluster_user = 'root';
        }
        else {
            return;
        }
    }
    my $cache_file = '/var/cpanel/cluster/' . $cluster_user . '/config/' . $clustermaster . '.cache';

    my $now          = time();
    my $config_mtime = ( stat( '/var/cpanel/cluster/' . $cluster_user . '/config/' . $clustermaster ) )[9];
    my $dns_config_ref;
    $dns_config_ref->{cache_filename} = $cache_file;

    if (   $config_mtime
        && $config_mtime < $now ) {
        my $config_cache_mtime = ( stat($cache_file) )[9];

        if ( $config_cache_mtime && $config_cache_mtime > $config_mtime ) {
            my $dnsrole_config_mtime = ( stat("/var/cpanel/cluster/$cluster_user/config/$clustermaster-dnsrole") )[9];

            if (
                   $config_cache_mtime > $dnsrole_config_mtime
                && $config_cache_mtime > ( $now - 86400 )    # expire after one day
            ) {
                if ( open my $cache_fh, '<', $cache_file ) {
                    eval { local $SIG{__DIE__}; local $SIG{__WARN__}; $dns_config_ref = Cpanel::AdminBin::Serializer::LoadFile($cache_fh); };
                    close($cache_fh);

                    if ( !$@ && $dns_config_ref && ref $dns_config_ref && $dns_config_ref->{'_VERSION'} eq $VERSION ) {
                        $dns_config_ref->{'_CACHED'} = 1;
                        return $dns_config_ref;
                    }
                }
                elsif ( $! != _ENOENT() ) {
                    warn "open(<, $cache_file): $!";
                }
            }
        }
    }

    # Settings
    my ( $host, $user, $pass, $dnsrole );

    if ( open my $config_fh, '<', '/var/cpanel/cluster/' . $cluster_user . '/config/' . $clustermaster ) {
        $user = readline $config_fh;
        chomp $user;

        if ( $user =~ /^#\s*version/ ) {    #new style
            local $/;
            $dns_config_ref = {
                map { ( split( /=/, $_, 2 ) )[ 0, 1 ] }
                  split( /\r?\n/, readline($config_fh) )
            };
        }
        else {
            $host = readline $config_fh;
            chomp $host;
            {
                local $/;
                $pass = readline($config_fh);
            }
            $dns_config_ref = {
                'user' => $user,
                'host' => $host,
                'pass' => $pass
            };
            return if ( !$user || !$host || !$pass );

            # Skip cluster member if not configured
        }
        close $config_fh;
    }

    # Role defaults to standalone. This configuration option is not required.
    if ( open my $srvconf_fh, '<', '/var/cpanel/cluster/' . $cluster_user . '/config/' . $clustermaster . '-dnsrole' ) {
        $dnsrole = readline $srvconf_fh;
        chomp $dnsrole;
        close $srvconf_fh;
    }
    $dnsrole ||= 'standalone';

    $dns_config_ref->{'_cluster_config_user'} = $cluster_user;
    $dns_config_ref->{'dnsrole'}              = $dnsrole;
    $dns_config_ref->{'_VERSION'}             = $VERSION;

    if ( $dns_config_ref->{'module'} eq 'cPanel' ) {

        # We need to store the ACTUAL hostname of the remote system
        # so that dnsadmin can tell if the request has already made
        # it to the remote system.
        #
        # The Cpanel::NameServer::Remote::cPanel will add
        # each hostname that has processed the cluster call
        # to the 'hosts_seen' field in order to allow the
        # system making the remote call to detect if the
        # cluster call has already made it to the remote
        # and avoid duplicate calls in a looped cluster.
        $dns_config_ref->{'hostname'} = _get_remote_cpanel_server_hostname($dns_config_ref);
    }

    # Case 63664: One of the parent directories is already root:root 0700, but
    # leave the cache file with the same reduced permissions as the original
    # file just in case.
    eval { Cpanel::FileUtils::Write::overwrite( $cache_file, Cpanel::AdminBin::Serializer::Dump($dns_config_ref), 0600 ); };

    return $dns_config_ref;
}

sub _get_remote_cpanel_server_hostname {
    my ($dns_config_ref) = @_;

    require cPanel::PublicAPI;
    require cPanel::PublicAPI::WHM;
    require cPanel::PublicAPI::WHM::API;
    my $public_api = cPanel::PublicAPI->new(
        'host'            => $dns_config_ref->{'host'},
        'user'            => $dns_config_ref->{'user'},
        'accesshash'      => $dns_config_ref->{'pass'},
        'keepalive'       => 0,
        'debug'           => 0,
        'usessl'          => 1,
        'ssl_verify_mode' => 0,
        'timeout'         => 5
    );

    my $hostname;
    local $@;
    eval {
        my $res = $public_api->api_gethostname();
        $hostname = $res->{'hostname'};
    };

    warn if $@;
    return $hostname;

}

1;
