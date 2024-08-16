package Cpanel::DNSLib::PeerConfig;

# cpanel - Cpanel/DNSLib/PeerConfig.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::Autodie::More::Lite ();

#
#   DO NOT 'use' HERE OR IT WILL BREAK SOURCE IP CHECK
#
our $VERSION = '4.0';    # Must match $Cpanel::DNSLib::Config::VERSION

###########################################################################
#
# Method:
#    getdnspeers
#
# Description:
#    This function returns an array of servers
#   that are configured to have changes written to them
#
# Arguments:
#
#   0 - $cluster_user - Optional
#                  Defaults to the current logged in
#                  user as defined by $ENV{'REMOTE_USER'}
#                  unless unique clustering is disabled
#                  for that user, then it defaults to root.
#
#                  The user to get the peers for
#                  Each reseller with the cluster priv
#                  may have their own set of
#                  servers to write changes to.
#
# Returns:
#     An array of hostnames of dns peers.
#

sub getdnspeers {
    return if !-e '/var/cpanel/useclusteringdns';

    my $cluster_user = shift || ( ( $ENV{'REMOTE_USER'} && -e '/var/cpanel/cluster/' . $ENV{'REMOTE_USER'} . '/uniquedns' ) ? $ENV{'REMOTE_USER'} : 'root' );

    return getdnspeerlist( [ 'write-only', 'sync' ], $cluster_user );
}

###########################################################################
#
# Method:
#    getdnspeerlist
#
# Description:
#    This function returns an array of servers
#    that a specific cluster_user has configured.
#
# Arguments:
#
#   0 - $mtypes - An array ref of peer types with one or more of:
#     - write-only
#     - sync
#     - standalone
#         OR
#           - A scalar containing one of the above peer types.
#
#   1 - $cluster_user - Optional
#                  Defaults to the current logged in
#                  user as defined by $ENV{'REMOTE_USER'}
#                  unless unique clustering is disabled
#                  for that user, then it defaults to root.
#
#                  The user to get the peers for
#                  Each reseller with the cluster priv
#                  may have their own set of
#                  servers to write changes to.
#
#   2 - $expire_cache -Optional
#                   Defaults to false.  Forces off reading of caches for this call.
#
# Returns:
#     An array of hostnames of dns peers.
#
sub getdnspeerlist {
    my ( $mtypes, $cluster_user, $expire_cache ) = @_;
    $cluster_user ||= ( ( $ENV{'REMOTE_USER'} && -e '/var/cpanel/cluster/' . $ENV{'REMOTE_USER'} . '/uniquedns' ) ? $ENV{'REMOTE_USER'} : 'root' );
    if ( !ref $mtypes ) { $mtypes = [$mtypes]; }

    $cluster_user =~ s/\///g;
    for ( 0 .. $#{$mtypes} ) {
        $mtypes->[$_] =~ s/\///g;
    }
    my $mtypes_file_name = join( '_', @{$mtypes} );

    my $config_dir_mtime;
    my $config_dir = "/var/cpanel/cluster/$cluster_user/config";
    return () unless Cpanel::Autodie::More::Lite::exists($config_dir);
    $config_dir_mtime = ( stat(_) )[9];    # Stat is saved so if the $config_dir changes we need to restat it

    #
    #  We have a cache for   $cluster_user, $mtypes
    #  We validate that the cache is newer then the contents of all the dnsrole files
    #
    my $cache_ok = 0;
    if ( ( my $cluster_config_cache_mtime = ( stat("$config_dir\_$mtypes_file_name.cache") )[9] ) ) {
        $cache_ok = 1;
        if ( $config_dir_mtime < $cluster_config_cache_mtime && opendir( my $config_dh, $config_dir ) ) {

            #
            # If we have any files that have an mtime newer then the cache mtime
            # we cannot use the cache
            #
            $cache_ok = 0 if grep { $_ =~ m/-dnsrole$/ && ( stat("$config_dir/$_") )[9] >= $cluster_config_cache_mtime } readdir($config_dh);
            close($config_dh);
        }
        else {
            $cache_ok = 0;
        }
    }

    #Forcible cache expiry needed in some scenarios
    $cache_ok = 0 if $expire_cache;

    #
    #  If we have a valid cache try to open it and read it in
    #
    if ($cache_ok) {
        my @PEERS;
        if ( open( my $cache_fh, '<', "$config_dir\_$mtypes_file_name.cache" ) ) {
            local $/;
            @PEERS = split( /\n/, readline($cache_fh) );
        }

        # The last line must be the $VERSION of this module
        # If it does not match it is an older/newer format, or file is incomplete
        if ( @PEERS && pop(@PEERS) eq $VERSION ) {
            return @PEERS;
        }
    }

    #
    # Update the cache is possible, otherwise just trasverse the list and fetch each peer's config
    #
    if ( $> == 0 ) {
        my @PEERS = _fetch_peers( $cluster_user, $mtypes );
        if ( open( my $cache_fh, '>', "$config_dir\_$mtypes_file_name.cache" ) ) {
            print {$cache_fh} join( "\n", @PEERS, $VERSION );
        }
        return @PEERS;
    }
    else {
        return _fetch_peers( $cluster_user, $mtypes );
    }
}

sub _fetch_peers ( $cluster_user, $mtypes ) {

    if ( !ref $mtypes ) { $mtypes = [$mtypes]; }
    my @PEERS;
    if ( opendir( my $config_dh, "/var/cpanel/cluster/$cluster_user/config" ) ) {
        foreach my $server ( grep { m/-dnsrole$/ } readdir($config_dh) ) {

            # Do not bother opening the file if the length of the data will never match
            my $file_size = ( stat("/var/cpanel/cluster/$cluster_user/config/$server") )[7];

            my $can_match = 0;

            # We do allow for a newline at the end of the file
            foreach my $mtype ( @{$mtypes} ) {
                next if ( $file_size != length $mtype && $file_size != ( length($mtype) + 1 ) );
                $can_match = 1;
                last;
            }

            next if !$can_match;

            if ( open my $srvconf_fh, '<', "/var/cpanel/cluster/$cluster_user/config/$server" ) {
                my $dnsrole = readline $srvconf_fh;
                chomp($dnsrole);
                close $srvconf_fh;
                if ( grep { $dnsrole eq $_ } @{$mtypes} ) {
                    $server =~ s/-dnsrole$//g;
                    next if !$server;
                    push @PEERS, $server;
                }
            }
        }
    }
    return @PEERS;
}

###########################################################################
#
# Method:
#    change_dns_role
#
# Description:
#    This function returns an array of servers
#    that a specific cluster_user has configured.
#
# Arguments:
#
#   0 - $server - The dns peer to alter the role for.
#
#   1 - $dnsrole - The new dns role:
#    sync       - Two way sync changes to the peer (write and read)
#    write-only - One way write changes to the peer (write only)
#    standalone - Send no changes
#
#   2 - $cluster_user - Optional
#                  Defaults to the current logged in
#                  user as defined by $ENV{'REMOTE_USER'}
#                  The user to get the peers for
#                  Each reseller with the cluster priv
#                  may have their own set of
#                  servers to write changes to.
#
# Returns:
#     Two argument array:
#       0 - Status (0 or 1)
#       1 - HTML Encoded Status Message
#
#
sub change_dns_role ( $server, $dnsrole, $cluster_user = undef ) {
    $cluster_user ||= $ENV{'REMOTE_USER'};

    if ( $server !~ m/\A[A-Za-z0-9:\.-]+\z/ ) {
        return ( 0, "The server contains invalid characters.\n" );
    }
    if ( $dnsrole !~ /\A(?:standalone|sync|write-only)\z/ ) {
        return ( 0, "The dnsrole is not valid.\n" );
    }

    my $html_safe_dnsrole = $dnsrole;
    my $html_safe_server  = $server;

    $html_safe_dnsrole =~ s/[^-_\w\.]+//g;
    $html_safe_server  =~ s/[^-_\w\.]+//g;

    if ( ( $dnsrole eq 'sync' || $dnsrole eq 'write-only' ) && !-e '/var/cpanel/cluster/root/config/' . $server ) {
        return ( 0, "For security reasons, the root user must add this server into the cluster before it can be made to synchronize dns records.  To accomplish this you or the server administrator must login as root and add $html_safe_server to the cluster." );
    }

    if ( open my $config_fh, '>', '/var/cpanel/cluster/' . $cluster_user . '/config/' . $server . '-dnsrole' ) {
        print {$config_fh} $dnsrole;
        close $config_fh;
    }
    else {
        return ( 0, "Failed to save changes: $!" );
    }

    return ( 1, "The new role for $html_safe_server is $html_safe_dnsrole." );
}

1;
