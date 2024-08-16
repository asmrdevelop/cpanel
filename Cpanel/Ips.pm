package Cpanel::Ips;

# cpanel - Cpanel/Ips.pm                           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::IP::Loopback  ();
use Cpanel::Ips::Fetch    ();
use Cpanel::Ips::Reserved ();

our $VERSION = '1.3';

my $SYSTEM_CONF_DIR = '/etc';

*fetchipslist             = *Cpanel::Ips::Fetch::fetchipslist;
*load_reserved_ips        = *Cpanel::Ips::Reserved::load_reserved_ips;
*load_reserved_ip_reasons = *Cpanel::Ips::Reserved::load_reserved_ip_reasons;
*load_apache_reserved_ips = *Cpanel::Ips::Reserved::load_apache_reserved_ips;

sub fetchiflist {
    my $ifcfg_ref = shift;
    if ( !ref $ifcfg_ref ) { $ifcfg_ref = fetchifcfg(); }

    return { map { $_->{'if'} => 1 } @{$ifcfg_ref} };
}

# Pass it a dotted quad netmask such as 255.255.255.0 and get back the number for the /$prefix value for it, such as /24
sub convert_quad_to_prefix {
    my ( $quad0, $quad1, $quad2, $quad3 ) = split( /\./, "@_" );
    my $num   = ( $quad0 * 16777216 ) + ( $quad1 * 65536 ) + ( $quad2 * 256 ) + $quad3;
    my $bin   = unpack( "B*", pack( "N", $num ) );
    my $count = ( $bin =~ tr/1/1/ );
    return $count;
}

sub convert_prefix_to_binary {
    my ($prefix) = @_;
    return ( 1, "1" x $prefix . "0" x ( 32 - $prefix ) );
}

sub convert_binary_to_quad {
    my ($binary) = @_;
    if ( length($binary) != 32 ) {
        return ( 0, "Invalid binary string: not 32 bits" );
    }

    # Break up binary string into 4 x 8bit sections
    my @quads;
    for ( 0 .. 3 ) {
        my $mult  = $_ * 8;
        my $eight = substr $binary, $mult, 8;
        push( @quads, $eight );
    }
    my $dotted_quad;
    foreach my $bitblock (@quads) {
        my $quad = 0;
        my (@bins) = split( //, $bitblock, 8 );
        $quad = ( ( $bins[0] * 128 ) + ( $bins[1] * 64 ) + ( $bins[2] * 32 ) + ( $bins[3] * 16 ) + ( $bins[4] * 8 ) + ( $bins[5] * 4 ) + ( $bins[6] * 2 ) + ( $bins[7] * 1 ) );
        $dotted_quad .= '.' . $quad;
    }
    $dotted_quad =~ s/^\.//;
    return ( 1, $dotted_quad );
}

sub convert_prefix_to_quad {
    my ($prefix) = @_;
    my ( $ret, $binprefix ) = convert_prefix_to_binary($prefix);
    ( $ret, my $quad ) = convert_binary_to_quad($binprefix);
    if ($ret) {
        return ( 1, $quad );
    }
    else {
        return ( 0, "Problem during conversion: $binprefix , $quad" );
    }
}

sub fetchifcfg {
    require Cpanel::Linux::RtNetlink;
    return [
        map {
            !Cpanel::IP::Loopback::is_loopback( $_->{'ip'} ) ? {
                'if'   => $_->{'label'},                                      #
                'ip'   => $_->{'ip'},                                         #
                'mask' => ( convert_prefix_to_quad( $_->{'prefix'} ) )[1],    #
              }
              : ()
        } @{ Cpanel::Linux::RtNetlink::get_interface_addresses('AF_INET') }
    ];
}

sub get_configured_ips_list {
    my $ips_ref = load_configured_ips();
    return keys %{$ips_ref};
}

sub load_configured_ips {
    return if !-e "$SYSTEM_CONF_DIR/ips";
    my %ips;
    if ( open my $ips_fh, '<', "$SYSTEM_CONF_DIR/ips" ) {
        while ( my $line = readline $ips_fh ) {
            next if $line !~ m/^\d+.\d+\.\d+\.\d+:\d+.\d+\.\d+\.\d+:\d+.\d+\.\d+\.\d+$/;
            chomp $line;
            my ( $ip, $netmask, $block ) = split( /:/, $line, 3 );
            $ips{$ip}{'netmask'} = $netmask;
            $ips{$ip}{'block'}   = $block;
        }
        close $ips_fh;
    }
    return \%ips;
}

sub is_private {
    my ($ip) = @_;
    return undef if !length $ip;
    return 1     if index( $ip, '127.' ) == 0;
    require Cpanel::IP::Utils;
    return Cpanel::IP::Utils::get_private_mask_bits_from_ip_address($ip) ? 1 : undef;
}

sub default_conf_dir {
    $SYSTEM_CONF_DIR = shift if @_;
    return $SYSTEM_CONF_DIR;
}

sub get_ip_info {
    my ( $ip, $netmask, $info_out ) = @_;

    my ( $ipp1, $ipp2, $ipp3, $ipp4 ) = split( /\./, $ip );
    my ( $npp1, $npp2, $npp3, $npp4 ) = split( /\./, $netmask );

    my $bc1 = $ipp1 | ( $npp1 ^ 255 );
    my $bc2 = $ipp2 | ( $npp2 ^ 255 );
    my $bc3 = $ipp3 | ( $npp3 ^ 255 );
    my $bc4 = $ipp4 | ( $npp4 ^ 255 );

    my $nc1 = $ipp1 & ($npp1);
    my $nc2 = $ipp2 & ($npp2);
    my $nc3 = $ipp3 & ($npp3);
    my $nc4 = $ipp4 & ($npp4);

    my $broadcast = $bc1 . '.' . $bc2 . '.' . $bc3 . '.' . $bc4;
    my $network   = $nc1 . '.' . $nc2 . '.' . $nc3 . '.' . $nc4;

    # Case 44602: For /31 and /32, only two or one address(es) are available
    # for the whole subnet, respectively
    if ( $ip eq $broadcast && $npp4 < 254 ) {
        return 0, "Cannot add address ${ip}: it is the address of the broadcast";
    }
    if ( $ip eq $network && $npp4 < 254 ) {
        return 0, "Cannot add address ${ip}: it is the address of the network";
    }

    $info_out->{'broadcast'} = $broadcast;
    $info_out->{'network'}   = $network;
    return 1;
}

1;
