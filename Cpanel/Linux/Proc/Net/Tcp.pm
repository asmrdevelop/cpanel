package Cpanel::Linux::Proc::Net::Tcp;

# cpanel - Cpanel/Linux/Proc/Net/Tcp.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

our $PROC_NET_TCP  = '/proc/net/tcp';
our $PROC_NET_TCP6 = '/proc/net/tcp6';

sub connection_lookup {
    my ( $remote_address, $remote_port, $local_address, $local_port ) = @_;

    # Fallback to /proc/net/tcp if netlink fails
    my ( $tcp_file, $remote_ltl_endian_hex_address, $remote_hex_port, $local_ltl_endian_hex_address, $local_hex_port );

    $remote_hex_port = _dec_port_to_hex_port($remote_port);
    $local_hex_port  = _dec_port_to_hex_port($local_port);

    if ( $remote_address =~ tr/:// ) {    #ipv6
        $tcp_file                      = $PROC_NET_TCP6;
        $remote_ltl_endian_hex_address = _ipv6_text_to_little_endian_hex_address($remote_address);
        $local_ltl_endian_hex_address  = _ipv6_text_to_little_endian_hex_address($local_address);
    }
    else {
        $tcp_file                      = $PROC_NET_TCP;
        $remote_ltl_endian_hex_address = _ipv4_txt_to_little_endian_hex_address($remote_address);
        $local_ltl_endian_hex_address  = _ipv4_txt_to_little_endian_hex_address($local_address);
    }

    if ( open( my $tcp_fh, '<', $tcp_file ) ) {
        my $uid;
        while ( readline($tcp_fh) ) {
            if (   m/^\s*\d+:\s+([\dA-F]{8}(?:[\dA-F]{24})?):([\dA-F]{4})\s+([\dA-F]{8}(?:[\dA-F]{24})?):([\dA-F]{4})\s+(\S+)\s+\S+\s+\S+\s+\S+\s+(\d+)/
                && $remote_ltl_endian_hex_address eq $1
                && $remote_hex_port eq $2
                && $local_ltl_endian_hex_address eq $3
                && $local_hex_port eq $4 ) {

                #my($remote_address, $remote_port, $local_address, $local_port, $state, $uid) = ($1, $2, $3, $4, $5, $6);
                #Exim::log_write("$remote_address, $remote_port, $local_address, $local_port, $state, $uid");
                $uid = $6;
                last;
            }

        }
        return $uid;

    }

    return;
}

sub _dec_port_to_hex_port {
    my ($dec_port) = @_;

    return sprintf( '%04X', $dec_port );
}

sub _ipv4_txt_to_little_endian_hex_address {
    my ($ipv4_txt) = @_;

    return sprintf( "%08X", unpack( 'V', pack( 'C4', split( /\D/, $ipv4_txt, 4 ) ) ) );
}

sub _ipv6_text_to_little_endian_hex_address {
    my ($ipv6_txt) = @_;

    require Cpanel::IP::Expand;    # hide from exim but not perlcc - not eval quoted

    my $hexip = '';
    my @ip    = split /:/, Cpanel::IP::Expand::expand_ip( $ipv6_txt, 6 );
    while (@ip) {
        my $block1 = shift @ip;
        my $block2 = shift @ip;
        $hexip .= uc substr( $block2, 2, 2 ) . uc substr( $block2, 0, 2 ) . uc substr( $block1, 2, 2 ) . uc substr( $block1, 0, 2 );
    }
    return $hexip;
}

1;
