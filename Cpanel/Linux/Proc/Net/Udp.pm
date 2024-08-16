package Cpanel::Linux::Proc::Net::Udp;

# cpanel - Cpanel/Linux/Proc/Net/Udp.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Linux::Proc::Net::Udp - Read UDP socket information from /proc.

=head1 SYNOPSIS

    my $udp4_ar = get_udp4_sockets();
    my $udp6_ar = get_udp6_sockets();

=head1 DESCRIPTION

This module is meant as a fallback for L<Cpanel::Sys::Net> on systems
that don’t implement the proper Netlink support.

Once support for CentOS 6 goes away, this module probably can as well.

=cut

#----------------------------------------------------------------------

use Cpanel::LoadFile      ();
use Cpanel::Socket::Micro ();

use constant {

    # accessed from tests
    _UDP4_PATH => '/proc/net/udp',
    _UDP6_PATH => '/proc/net/udp6',
};

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 get_udp4_sockets()

See L<Cpanel::Sys::Net>’s function of the same name.

=cut

sub get_udp4_sockets {
    return _get_sockets( _UDP4_PATH(), \&_xform_ip4 );
}

#----------------------------------------------------------------------

=head2 get_udp6_sockets()

See L<Cpanel::Sys::Net>’s function of the same name.

=cut

sub get_udp6_sockets {
    return _get_sockets( _UDP6_PATH(), \&_xform_ip6 );
}

#----------------------------------------------------------------------

sub _xform_ip6 {
    my ($socket_hr) = @_;

    for my $val ( @{$socket_hr}{ 'src', 'dst' } ) {

        $val = pack 'H*', $val;

        # $val is now a binary string of 4 little-endian u32s.
        # We need those to be big-endian, though, so after we unpack
        # each u32 into its own string of 4 bytes, we reverse each one.
        # Finally, we concat the reversed bytes into a single
        # binary string, which we can feed into inet6_ntoa to get
        # our canonical-format IPv6 address.

        $val = Cpanel::Socket::Micro::inet6_ntoa( join( q<>, map { scalar reverse } unpack '(a4)*', $val ) );
    }

    return;
}

sub _xform_ip4 {
    my ($socket_hr) = @_;

    # NB: /proc shows the addresses in native order,
    # which for us little-endian types is reverse from network order.
    $_ = Cpanel::Socket::Micro::inet_ntoa( scalar reverse pack 'H*', $_ ) for @{$socket_hr}{ 'src', 'dst' };

    return;
}

sub _get_sockets {
    my ( $path, $xform_cr ) = @_;

    my $buf = Cpanel::LoadFile::load($path);

    my @sockets;

    my $skipped_first;

    for my $line ( split m<\n>, $buf ) {
        if ( !$skipped_first ) {
            $skipped_first = 1;
            next;
        }

        substr( $line, 0, 2 + index( $line, ':' ) ) = q<>;

        my ( $src, $dst, $state, $queue, undef, undef, $uid, undef, $inode ) = split m< +>, $line;

        ( $src, my $sport ) = split m<:>, $src;
        ( $dst, my $dport ) = split m<:>, $dst;
        my ( $wqueue, $rqueue ) = split m<:>, $queue;

        #$_ = hex for @{$socket_hr}{ 'sport', 'dport', 'state', 'wqueue', 'rqueue' };
        $_ = hex for ( $sport, $dport, $state, $wqueue, $rqueue );

        my %socket = (
            src   => $src,
            sport => $sport,

            dst   => $dst,
            dport => $dport,

            state => $state,

            wqueue => $wqueue,
            rqueue => $rqueue,

            uid   => $uid,
            inode => $inode,
        );

        $xform_cr->( \%socket );

        push @sockets, \%socket;
    }

    return \@sockets;
}

1;
