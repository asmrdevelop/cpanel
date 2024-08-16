# cpanel - Cpanel/DNSLib/PeerStatus.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::DNSLib::PeerStatus;

use strict;
use warnings;

use Cpanel::Autodie::More::Lite        ();
use Cpanel::DIp::MainIP                ();
use Cpanel::DNSLib::Config             ();
use Cpanel::DNSLib::PeerConfig         ();
use Cpanel::Encoder::URI               ();
use Cpanel::Hostname                   ();
use Cpanel::NameServer::Remote::cPanel ();
use Cpanel::NAT::Object                ();
use Cpanel::Parallelizer               ();    ## PPI USE OK ~ list context input functions trip this erroneously
use Cpanel::Version                    ();
use Whostmgr::ACLS                     ();

use Capture::Tiny qw{capture_stderr};

=head1 NAME

Cpanel::DNSLib::PeerStatus

=head1 DESCRIPTION

One-stop shop for figuring out what the hey is going on with the DNS cluster this machine coordinates.

=head1 SUBROUTINES

=cut

our $serviceinfo;

sub _get_cache_path {
    my ( $user, $host ) = @_;
    return "/var/cpanel/cluster/$user/config/$host-state.json";
}

sub _get_from_cache {
    my ( $user, $host ) = @_;
    my $file = _get_cache_path( $user, $host );
    return undef if !-f $file || ( ( ( stat _ )[9] ) < ( time() - 86400 ) );
    require Cpanel::JSON;
    my $cached = Cpanel::JSON::LoadFile($file);
    return $cached;
}

sub _save_to_cache {
    my ( $user, $host, $data ) = @_;
    my $file = _get_cache_path( $user, $host );
    require Cpanel::Transaction::File::JSON;
    my $transaction = Cpanel::Transaction::File::JSON->new( path => $file, permissions => 0600 );
    $transaction->set_data($data);
    $transaction->save_or_die();
    return $data;
}

sub set_change_expected {
    my ( $user, $host, $state ) = @_;
    my $cache = _get_from_cache( $user, $host );
    return unless $cache;
    foreach my $key ( keys(%$state) ) {
        $cache->{$key} = $state->{$key};
    }
    return _save_to_cache( $user, $host, $cache );
}

=head2 invalidate_and_refresh_cache( STRING $user, STRING $host )

Wrapper around getpeerstate which forces cache invalidation.

=cut

sub invalidate_and_refresh_cache {
    my ( $user, $host ) = @_;
    return getpeerstate( $user, $host, 1 );
}

=head2 getpeerstate( STRING $user, STRING $host, BOOL $invalidate_cache )

Get the state information for a given peer in the DNS cluster.

Optionally reject the cache and gather the remote data.

Dies in the event you ask for a cluster member that does not exist.

=cut

sub getpeerstate {    ## no critic (ProhibitExcessComplexity)
    my ( $user, $host, $invalidate_cache ) = @_;

    for ( $user, $host ) {
        die "Invalid: $_" if -1 != index( $_, '/' );
    }

    if ( !Cpanel::Autodie::More::Lite::exists("/var/cpanel/cluster/$user/config/$host") ) {
        die "No such cluster member '$host' configured for user '$user'.";
    }

    my $cached;
    $cached = _get_from_cache( $user, $host ) unless !-f _get_cache_path( $user, $host ) || $invalidate_cache;
    return $cached if $cached;

    my $obj = Cpanel::DNSLib::Config::get_cluster_member_config( $host, $user );

    #XXX work around inconsistent data, this can be anything
    $obj->{hostname} //= defined( $obj->{host} ) && $obj->{host} ne $host ? $obj->{host} : "unknown";
    $obj->{host} = $host;

    $obj->{disabled} = Cpanel::Autodie::More::Lite::exists("/var/cpanel/clusterqueue/status/$host-down") ? 1 : 0;
    if ( !$obj->{disabled} && $obj->{module} eq 'cPanel' ) {

        my $bulk_info = _get_infos_bulk( $obj->{host} );

        #Assume things are OK unless we get explicit evidence otherwise
        $obj->{has_good_privs} = 1;
        if ( ref $bulk_info eq 'HASH' && $bulk_info->{metadata} ) {

            $obj->{has_good_privs} = $bulk_info->{metadata}->{reason} !~ m/required privileges/i;
            $obj->{status}         = $bulk_info->{metadata}->{reason} ? 1 : 0;

            #Needed for _get_alt_dns_servers below
            $serviceinfo->{ $obj->{host} } = ( grep { $_->{metadata}{command} eq 'installed_versions' } @{ $bulk_info->{data}{result} } )[0];
            my $altdns = _get_alt_dns_servers($obj);
            $obj->{dns_server}  = $altdns ? $altdns                                       : 'bind';
            $obj->{dns_version} = $altdns ? $serviceinfo->{ $obj->{host} }{data}{$altdns} : $serviceinfo->{ $obj->{host} }{data}{bind};

            foreach my $return ( @{ $bulk_info->{data}{result} } ) {
                next unless $return->{metadata}{result};
                my $command = $return->{metadata}{command} || '';
                if ( $command eq 'servicestatus' ) {
                    $obj->{dns_server_disabled}  = !$return->{data}{service}[0]{enabled};
                    $obj->{dns_server_running}   = $return->{data}{service}[0]{running};
                    $obj->{dns_server_monitored} = $return->{data}{service}[0]{monitored};
                }
                $obj->{has_reverse_trust} = $return->{data}{has_trust} if $command eq 'cluster_member_has_trust_with';
                $obj->{version}           = $return->{data}{version}   if $command eq 'version';
            }
        }

        #Ok, if we *couldn't* grab the extended info, let's at least get the version so that we are compatible with old cluster members
        $obj->{version} = _do_whmapi( 'version', $obj ) unless $obj->{version};

        ( $obj->{dns_mmversion} ) = $obj->{dns_version} =~ /^(\d+\.\d+)/ if defined $obj->{dns_version};

        #TODO wat do about other types of cluster modules?
        if ( $obj->{version} ) {
            ( $obj->{mmversion} ) = $obj->{version} =~ /^(\d+\.\d+)/;
        }

        #If we couldn't figure this out we're probably down
        $obj->{error} = defined $obj->{status} ? '' : "Could not communicate with remote API server.";
    }

    # Use this as an analog for "this version supports dnssec clustering", came in at same time
    # Unfortunately we have to check versions due to people having RPMUP being disabled
    $obj->{dnssec} =
         defined $obj->{dns_server}
      && defined $obj->{dns_version}
      && defined $obj->{dns_mmversion}
      && $obj->{module} eq 'cPanel'
      && ( ( $obj->{dns_server} eq 'powerdns' )
        && ( $obj->{dns_mmversion} >= 4 ) );

    _save_to_cache( $user, $host, $obj );
    return $obj;
}

=head2 %status = getclusterstatus( BOOL invalidate_cache )

Returns a list of key/value pairs describing the members/peers in your DNS cluster.

=over

=item coordinator => hash ref of info about the local machine, and it's dns capabilities etc.

=item sync => array ref of said members of the cluster, their capabilities and type

=item write-only => array ref of said members of cluster, their capabilities and type

=item standalone => array ref of said members of cluster, their capabilities and type

=back

Caches data for 24 hours, or invalidates based on user request.

=cut

sub _lookup_by_user {
    my ( $user, $invalidate_cache ) = @_;
    return map {
        my @members = grep { defined $_ } @{
            [
                Cpanel::Parallelizer::pmap(
                    sub {
                        my $o = getpeerstate( $user, $_, $invalidate_cache );
                        $o->{cluster_config_user} = delete $o->{_cluster_config_user} if ref $o eq 'HASH' && $o->{_cluster_config_user};
                        $o;
                    },
                    Cpanel::DNSLib::PeerConfig::getdnspeerlist( [$_] )
                )
            ]
        };
        $_ => \@members;
    } qw{standalone write-only sync};
}

sub getclusterstatus {
    my $invalidate_cache = shift;

    my $user           = $ENV{REMOTE_USER} // 'root';
    my $localversion   = Cpanel::Version::get_version_full();
    my %cluster_status = _lookup_by_user( $user, $invalidate_cache );

    # Ensure the resellers can see what they inherit from root
    if ( $user ne 'root' ) {
        local $ENV{REMOTE_USER} = 'root';
        $user = $ENV{REMOTE_USER};
        my %root_hosts = _lookup_by_user( $user, $invalidate_cache );
        foreach my $dnsrole ( keys(%root_hosts) ) {
            push( @{ $cluster_status{$dnsrole} }, @{ $root_hosts{$dnsrole} } );
        }
    }

    my $hostname = Cpanel::Hostname::gethostname();

    #Insert this host into the standalone list
    require Cpanel::DNSSEC::Available;
    $cluster_status{coordinator} = {
        hostname            => $hostname,
        host                => '127.0.0.1',
        cluster_config_user => $user,
        disabled            => 0,
        module              => 'cPanel',
        version             => $localversion,
        _VERSION            => $Cpanel::NameServer::Remote::cPanel::VERSION,
        dnssec              => Cpanel::DNSSEC::Available::dnssec_is_available(),
        debug               => 0,
    };

    ( $cluster_status{coordinator}{mmversion} ) = $localversion =~ /^(\d+\.\d+)/;
    return %cluster_status;
}

sub _get_alt_dns_servers {
    my $authen      = shift;
    my %dns_servers = map { $_ => $serviceinfo->{ $authen->{host} }{data}{$_} } grep {
        my $subj = $_;
        ( grep { $subj eq $_ } qw{powerdns} ) ? $serviceinfo->{ $authen->{host} }{data}{$subj} : undef;
    } keys( %{ $serviceinfo->{ $authen->{host} }{data} } );

    return ( keys(%dns_servers) )[0];
}

our %remotens;

sub _do_whmapi {
    my ( $call, $authen, $args ) = @_;

    return unless $authen->{host} && $authen->{user} && $authen->{pass};

    $remotens{ $authen->{host} } //= Cpanel::NameServer::Remote::cPanel->new(
        host    => $authen->{host},
        user    => $authen->{user},
        pass    => $authen->{pass},
        ip      => $authen->{host},
        timeout => 7,
    );

    my ( $ret, $ex );
    my $stderr = capture_stderr {
        local $@;
        $ret = eval { $remotens{ $authen->{host} }->{publicapi}->whm_api( $call, $args ) };
        $ex  = $@;
    };

    if ( $ex || ( !$ret && $stderr ) ) {
        require Cpanel::Debug;
        Cpanel::Debug::log_warn( $ex || $stderr );
    }

    return $ret;
}

sub _get_infos_bulk {
    my ($host) = @_;
    my $user   = $ENV{REMOTE_USER} || 'root';
    my $authen = Cpanel::DNSLib::Config::get_cluster_member_config( $host, $user );
    $authen->{host} = $host;

    # when determining reverse trust, we have to ask whether they trust *us*
    # but due to the way we store this, we can't ask for the hostname reliably
    # and we have to ask for both "real" and "nat" IP because sometimes we just store an IP.
    my $internal_ip = Cpanel::DIp::MainIP::getmainserverip();
    my $NAT_obj     = Cpanel::NAT::Object->new();
    my $NAT_ip      = $NAT_obj->get_public_ip_raw($internal_ip);

    my %request = (
        version            => { 'api.version' => 1 },
        installed_versions => { 'api.version' => 1 },
        servicestatus      => { 'api.version' => 1, service => 'named' },
    );

    my $result = _do_whmapi( 'batch', $authen, _build_bulk_whmreq(%request) );

    if ( $result && ref $result eq 'HASH' && $result->{metadata}{result} ) {

        # The cluster_member_has_trust_with WHM API method was not added until v84 and
        # calling the batch API when one of the API methods doesn’t exist causes the
        # entire batch to fail with a 500 error. So we need to check the result of the
        # version API call to see if this is a thing we can even do.
        my $has_minimum_version;

        foreach my $subresult ( @{ $result->{data}{result} } ) {
            if ( ref $subresult eq 'HASH' && $subresult->{metadata}{command} && $subresult->{metadata}{command} eq 'version' ) {
                if ( $subresult->{metadata}{result} ) {
                    require Cpanel::Version::Compare;
                    $has_minimum_version = Cpanel::Version::Compare::compare_major_release( $subresult->{data}{version}, '>=', '11.84' );
                }
                last;
            }
        }

        if ($has_minimum_version) {

            my $trust_query = 'api.version=1&host=' . Cpanel::Encoder::URI::uri_encode_str($internal_ip);

            if ($NAT_ip) {
                $trust_query .= '&althost=' . Cpanel::Encoder::URI::uri_encode_str($NAT_ip);
            }

            push @{ $result->{data}{result} }, _do_whmapi( 'cluster_member_has_trust_with', $authen, $trust_query );
        }

    }

    return $result;
}

sub _build_bulk_whmreq {
    my (%input) = @_;
    my @query_string = ("api.version=1");
    push(
        @query_string,
        map {
            my $command = $_;
            my $args    = $input{$command};
            join( '=', 'command', Cpanel::Encoder::URI::uri_encode_str( "$_?" . ( join( '&', ( map { $_ . "=" . $args->{$_} } sort keys(%$args) ) ) ) ) )
        } sort keys(%input)
    );
    return join( '&', @query_string );
}

=head2 check_local_kit($invalidate_cache)

The idea here is that all servers will iContact based on this to make the servers operator know about inconsistent
cluster states so that they might remediate them BEFORE they use the footgun manually running synczones,
or as an iContact to let them know things are bad when synczones is fired as part of an automated process.

If $invalidate_cache is set, the cache will be invalidated immediately instead of after the usual expiration time.

Returns an array of error types the cluster as currently configured has.

=cut

sub check_local_kit {
    my $invalidate_cache = shift;

    my @problems;
    my %status = Cpanel::DNSLib::PeerStatus::getclusterstatus($invalidate_cache);

    my @disabled  = grep { $_->{disabled} }            ( @{ $status{sync} }, @{ $status{'write-only'} }, @{ $status{standalone} } );
    my @peertraps = grep { $_->{dns_server_disabled} } ( @{ $status{sync} }, @{ $status{'write-only'} } );
    my @nodnssec  = grep { !$_->{dnssec} && !$_->{dns_server_disabled} } ( @{ $status{sync} }, @{ $status{'write-only'} } );
    my @deadpeers = grep { !$_->{dns_server_running} && !$_->{dns_server_disabled} && !$_->{disabled} } ( @{ $status{sync} }, @{ $status{'write-only'} } );

    push( @problems, "peers_without_dnssec" ) if @nodnssec && $status{coordinator}{dnssec};

    # Time to worry about other cluster members
    push( @problems, "disabled_peers" ) if @disabled;
    push( @problems, "peer_zonetrap" )  if @peertraps;
    push( @problems, "dead_peers" )     if @deadpeers;

    return @problems;
}

=head2 upgrade_cluster_member($server, $user)

Upgrade the provided cluster member to PowerDNS.

Returns BOOL as to whether or not it worked.

=cut

sub upgrade_cluster_member {
    my ( $server, $user ) = @_;
    _validate_user( $user, $server );

    my $obj = _try_and_get_config( $server, $user );
    $obj->{host} = $server;    #override hostname, this can be bunk

    my $ret = _do_whmapi( 'set_nameserver', $obj, { nameserver => 'powerdns' } );
    if ( ( ref $ret eq 'HASH' ) && ( ref $ret->{metadata} eq 'HASH' ) && $ret->{metadata}->{reason} && ( $ret->{metadata}->{reason} eq 'OK' ) ) {
        set_change_expected( $user, $server, { dns_server => 'powerdns', dnssec => 1 } );
        return 1;
    }
    return 0;
}

=head2 restart_cluster_member($server, $user)

Restart the provided cluster member's DNS server.

Returns BOOL as to whether or not it worked.

=cut

sub restart_cluster_member {
    my ( $server, $user ) = @_;
    _validate_user( $user, $server );

    my $obj = _try_and_get_config( $server, $user );
    $obj->{host} = $server;    #override hostname, this can be bunk

    my $ret = _do_whmapi( 'restartservice', $obj, { service => 'named', queue_task => 1 } );
    if ( ( ref $ret eq 'HASH' ) && ( ref $ret->{metadata} eq 'HASH' ) && $ret->{metadata}->{result} ) {
        set_change_expected( $user, $server, { dns_server_running => 1 } );
        return 1;
    }
    return 0;
}

=head2 monitor_cluster_member($server, $user)

Configure monitoring for the provided cluster member's DNS server.

Returns BOOL as to whether or not it worked.

=cut

sub monitor_cluster_member {
    my ( $server, $user ) = @_;
    _validate_user( $user, $server );

    my $obj = _try_and_get_config( $server, $user );
    $obj->{host} = $server;    #override hostname, this can be bunk

    my $ret = _do_whmapi( 'configureservice', $obj, { service => 'named', monitored => 1 } );
    if ( ( ref $ret eq 'HASH' ) && ( ref $ret->{metadata} eq 'HASH' ) && $ret->{metadata}->{result} ) {
        set_change_expected( $user, $server, { dns_server_monitored => 1 } );
        return 1;
    }
    return 0;
}

sub _validate_user {
    my ( $user, $server ) = @_;

    die "User passed is not the effective user running this script." unless ( getpwuid $> )[0] eq $user;
    $ENV{REMOTE_USER} ||= $user;

    Whostmgr::ACLS::init_acls();

    #Security -- verify you are who you say you are, and that you own this cluster member
    if ( !Whostmgr::ACLS::hasroot() ) {

        die "The clustering ACL is required to make this call." unless Whostmgr::ACLS::checkacl('clustering');

        my $info = getpeerstate( $user, $server );
        die "You do not control the cluster member '$server'." unless $info->{_cluster_config_user} eq $user;
    }
    return 1;
}

=head2 has_reverse_trust($server_ip)

Basically figure out if said cluster member even knows it's part of a cluster.

Intended to be run by peers, rather than the rest of this which is intended to be run by the coordinator
Note how we are running this ON REMOTE SERVERS above.

Returns BOOL.

=cut

sub has_reverse_trust {
    my @servers = @_;
    my $user    = $ENV{REMOTE_USER} || 'root';
    my $obj;
    foreach my $server (@servers) {
        $obj = _try_and_get_config( $server, $user );
        last if $obj;
    }
    return !!$obj;
}

#If we can't get the config, it might be we had a hostname passed in, do inet_aton then
sub _try_and_get_config {
    my ( $server, $user ) = @_;
    return unless $server;
    my $obj = eval { Cpanel::DNSLib::Config::get_cluster_member_config( $server, $user ) };
    if ( !$obj ) {

        #Read all the config files so we can see if any of them have this hostname
        my @all_ips = map { Cpanel::DNSLib::PeerConfig::getdnspeerlist( [$_] ) } qw{standalone write-only sync};
        foreach my $ip (@all_ips) {
            my $candidate = Cpanel::DNSLib::Config::get_cluster_member_config( $ip, $user );
            return $candidate if $candidate->{host} && $candidate->{host} eq $server;
        }
    }
    return $obj;
}

1;
