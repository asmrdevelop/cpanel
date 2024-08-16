package Cpanel::DIp::MainIP;

# cpanel - Cpanel/DIp/MainIP.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadWwwAcctConf ();
use Cpanel::GlobalCache             ();
use Cpanel::IP::Bound               ();
use Cpanel::LoadFile                ();
use Cpanel::NAT                     ();
use Cpanel::Debug                   ();
use Cpanel::Validate::IP::v4        ();

our $VERSION = '1.5';

my $PRODUCT_CONF_DIR = '/var/cpanel';
my $SYSTEM_CONF_DIR  = '/etc';
my $SYSTEM_SBIN_DIR  = '/sbin';

my $cachedmainip   = q{};
my $cachedserverip = q{};

#########################################################################
# getmainsharedip (was previously called getmainip but that was confusing)
# Returns the main shared IP specified in /etc/wwwacct.conf
# only if it is properly configured
#
# We describe this as:
# The IPv4 address (only one address) to use to set up shared IPv4 virtual hosts.
#########################################################################
*getmainip = *getmainsharedip;

sub getmainsharedip {
    return $cachedmainip if ( $cachedmainip ne '' );

    my $wwwaccthash_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();
    my $addr            = q{};

    if ( exists $wwwaccthash_ref->{'ADDR'} ) {
        if ( !length $wwwaccthash_ref->{'ADDR'} ) {
            return ( $cachedmainip = getmainserverip() );
        }
        elsif ( !Cpanel::Validate::IP::v4::is_valid_ipv4( $wwwaccthash_ref->{'ADDR'} ) && -x "$SYSTEM_SBIN_DIR/ip" ) {
            return ( $cachedmainip = getmainserverip() );
        }
        elsif ( !-x "$SYSTEM_SBIN_DIR/ip" ) {
            return ( $cachedmainip = $wwwaccthash_ref->{'ADDR'} );
        }
        $addr = $wwwaccthash_ref->{'ADDR'};
    }

    if ( !-x "$SYSTEM_SBIN_DIR/ip" ) {
        Cpanel::Debug::log_warn("Working ip binary required to determine IP address. Please check the permissions of $SYSTEM_SBIN_DIR/ip");
        return;
    }

    return ( $cachedmainip = $addr ) if Cpanel::IP::Bound::ipv4_is_bound($addr);

    my $mainserverip = getmainserverip();

    $cachedmainip = $mainserverip;

    return $mainserverip;
}

######################################################################
# getmainserverip AKA get_default_outbound_ip_address
#
# This is the IP address that outbound connections from the server
# will use when no explict outbound IP address is specified
#
# This is usually first IP of eth0 or ETHDEV (from /etc/wwwacct.conf),
# however based on the server's network settings it may not always be
# the first one.  Each time scripts/maintenance runs during update
# it will call scripts/mainipcheck which will populate
# $PRODUCT_CONF_DIR/mainip with the IP that the server is actually
# using to make outbound connections one one is not specified AKA
# the default outbound IP address.
######################################################################
sub getmainserverip {
    return $cachedserverip if length $cachedserverip;

    # /var/cpanel/mainip is updated via scripts/mainipcheck
    my $oldmainip = Cpanel::LoadFile::loadfile("$PRODUCT_CONF_DIR/mainip");
    $oldmainip =~ tr{ \t\r\n}{}d if length $oldmainip;

    if ( Cpanel::Validate::IP::v4::is_valid_ipv4($oldmainip) ) {
        $cachedserverip = $oldmainip;
        return $oldmainip;
    }

    my $wwwaccthash_ref = Cpanel::Config::LoadWwwAcctConf::loadwwwacctconf();

    my $addr   = $wwwaccthash_ref->{'ADDR'}   // q{};
    my $ethdev = $wwwaccthash_ref->{'ETHDEV'} // q{};

    if ( !-x "$SYSTEM_SBIN_DIR/ip" ) {
        return $addr if length $addr;
        Cpanel::Debug::log_die("Fatal error: $SYSTEM_SBIN_DIR/ip is not executable, determining main server IP impossible");
    }

    # Get all alias IPs in /etc/rc.conf
    # These are filtered out and considered to not be the primary IP on the system.
    my $wwwacct_conf_mtime = ( stat($Cpanel::Config::LoadWwwAcctConf::wwwacctconf) )[9];
    my $ipconfig_mtime     = 43200;                                                        #12 hours
    if ( !$wwwacct_conf_mtime ) {

        # no wwwacct.conf yet (likely an initial install)
        $ipconfig_mtime = 1;
    }
    else {
        my $sec_since_wwwacct_conf_modified = ( time() - $wwwacct_conf_mtime );
        if ( $sec_since_wwwacct_conf_modified < $ipconfig_mtime ) {

            # If the wwwacct.conf was modified shorter then $ipconfig_mtime
            # we reduce it to the time since wwwacct.conf was modified with a 60
            # second buffer for extra safety
            $ipconfig_mtime = $sec_since_wwwacct_conf_modified - 60;
        }
    }
    my $thisip = _get_first_valid_ip( [ split( /\n/, Cpanel::GlobalCache::cachedmcommand( 'cpanel', $ipconfig_mtime, "$SYSTEM_SBIN_DIR/ip", '-4', 'addr', 'show', $ethdev eq '' ? () : $ethdev ) ) ] );

    return ( $cachedserverip = $thisip ) if $thisip;

    # Try again
    my $ips;
    my $retry_ok = 0;
    if ( !length $ethdev ) {
        require Cpanel::CachedCommand;
        $ips = Cpanel::CachedCommand::noncachedcommand( "$SYSTEM_SBIN_DIR/ip", '-4', 'addr', 'show' );
    }
    else {
        $retry_ok = 1;
        require Cpanel::CachedCommand;
        $ips = Cpanel::CachedCommand::noncachedcommand( "$SYSTEM_SBIN_DIR/ip", '-4', 'addr', 'show', $ethdev );
    }
    $thisip = _get_first_valid_ip( [ split( /\n/, $ips ) ] );
    return ( $cachedserverip = $thisip ) if $thisip;

    # Try again -- they have an invalid setting for ETHDEV
    if ($retry_ok) {
        require Cpanel::CachedCommand;
        $ips    = Cpanel::CachedCommand::noncachedcommand( "$SYSTEM_SBIN_DIR/ip", '-4', 'addr', 'show' );
        $thisip = _get_first_valid_ip( [ split( /\n/, $ips ) ] );
        return ( $cachedserverip = $thisip ) if $thisip;
    }

    if ( $ethdev ne '' ) {
        Cpanel::Debug::log_warn("No IP address found on $ethdev, make sure device is correctly configured, returning 0.0.0.0");
    }
    else {
        Cpanel::Debug::log_warn("No IP address found, returning 0.0.0.0");
    }
    return '0.0.0.0';
}

######################################################################
# getpublicmainserverip
# Returns the public IP of mainservip
######################################################################
sub getpublicmainserverip {
    return Cpanel::NAT::get_public_ip( getmainserverip() );
}

sub clearcache {
    $cachedmainip   = '';
    $cachedserverip = '';

    if ( $INC{'Cpanel/DIp.pm'} ) {
        Cpanel::DIp::clearcache();
    }
    return;
}

# Data mocking routine
sub default_product_dir {
    $PRODUCT_CONF_DIR = shift if @_;
    return $PRODUCT_CONF_DIR;
}

sub default_conf_dir {
    $SYSTEM_CONF_DIR = shift if @_;
    return $SYSTEM_CONF_DIR;
}

sub default_sbin_dir {
    $SYSTEM_SBIN_DIR = shift if @_;
    return $SYSTEM_SBIN_DIR;
}

sub _get_first_valid_ip {

    my ($ips_ref) = @_;

    require Cpanel::Regex;
    require Cpanel::IP::Loopback;

    # Problem exists here if there are multiple IPs that are in @IPS,
    # the first one will be chosen that does not match Cpanel::IP::Loopback::is_loopback
    # This is not necessarily the main IP. This might occur because IPs are
    # set manually via ip.
    foreach my $ip (@$ips_ref) {
        if ( $ip =~ m{ [\s\:] ($Cpanel::Regex::regex{'ipv4'}) }xoms ) {
            my $thisip = $1;
            if ( !Cpanel::IP::Loopback::is_loopback($thisip) ) {
                return $thisip;
            }
        }
    }
    return undef;
}

1;
