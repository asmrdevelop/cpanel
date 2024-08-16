package Cpanel::Sys::Net;

# cpanel - Cpanel/Sys/Net.pm                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::Sys::Net - Query the system for networking information

=head1 SYNOPSIS

    my $tcp4_ar = get_tcp4_sockets();
    my $tcp6_ar = get_tcp6_sockets();

    my $udp4_ar = get_udp4_sockets();
    my $udp6_ar = get_udp6_sockets();

=cut

#----------------------------------------------------------------------

use Cpanel::Autodie           ();
use Cpanel::Kernel            ();
use Cpanel::Linux::Netlink    ();
use Cpanel::Socket::Constants ();
use Cpanel::Socket::Micro     ();
use Cpanel::Pack              ();
use Cpanel::Try               ();

use constant _IP4_SOCKID_TEMPLATE => (
    sport => 'n',
    dport => 'n',

    # An IPv4 address is 4 octets.
    src => 'a4 x[LLL]',    # ignore last 3 longs

    # ignore last 3 longs, interface, and cookie
    dst => 'a4 x[LLL L LL]',
);

use constant _IP6_SOCKID_TEMPLATE => (
    sport => 'n',
    dport => 'n',

    # An IPv6 address is eight u16’s (network order).
    src => 'a16',

    dst => 'a16 x[L LL]',    # ignore “if” (interface) and cookie
);

# sock_diag.h
use constant {
    TCPDIAG_GETSOCK => 18,

    # accessed from tests
    SOCK_DIAG_BY_FAMILY => 20,

    # Request all sockets in any TCP state.
    TCPF_ALL => 0xfff,

    _IP4_INET_DIAG_MSG_TEMPLATE => [
        state => 'x C xx',    # ignore family, timer, retrans
        _IP4_SOCKID_TEMPLATE(),
        rqueue => 'x4 L',     # ignore expires
        wqueue => 'L',
        uid    => 'L',
        inode  => 'L',
    ],

    _IP6_INET_DIAG_MSG_TEMPLATE => [
        state => 'x C xx',    # ignore family, timer, retrans
        _IP6_SOCKID_TEMPLATE(),
        rqueue => 'x4 L',     # ignore expires
        wqueue => 'L',
        uid    => 'L',
        inode  => 'L',
    ],
};

=head1 FUNCTIONS

=head2 $SOCKETS_AR = get_tcp4_sockets()

Returns data about the system’s currently open IPv4 TCP sockets.

The return is a list of hashes, each of which contains the following:

=over

=item * C<src> - source address, in dotted-quad format

=item * C<sport> - source port

=item * C<dst> - destination address, in dotted-quad format

=item * C<dport> - source port

=item * C<inode>

=item * C<rqueue> - receive queue size, in bytes

=item * C<wqueue> - write queue size, in bytes

=item * C<state> - a number (e.g., TCP_ESTABLISHED)

=item * C<uid>

=back

=cut

sub get_tcp4_sockets {
    return _normalize_ip4( _get_sockets_from_netlink_tcp_diag( $Cpanel::Socket::Constants::AF_INET, _IP4_INET_DIAG_MSG_TEMPLATE() ) );
}

#----------------------------------------------------------------------

=head2 $SOCKETS_AR = get_tcp6_sockets()

Like C<get_tcp4_sockets()> but for IPv6.

C<src> and C<dst> are in colon-separated hextets.

=cut

sub get_tcp6_sockets {
    return _normalize_ip6( _get_sockets_from_netlink_tcp_diag( $Cpanel::Socket::Constants::AF_INET6, _IP6_INET_DIAG_MSG_TEMPLATE() ) );
}

#----------------------------------------------------------------------

=head2 $SOCKETS_AR = get_udp4_sockets()

Like C<get_tcp4_sockets()> but for UDP.

=cut

sub get_udp4_sockets {
    my $ar;

    Cpanel::Try::try(
        sub {
            $ar = _normalize_ip4( _get_udp_sockets_from_netlink_sock_diag( $Cpanel::Socket::Constants::AF_INET, _IP4_INET_DIAG_MSG_TEMPLATE() ) );
        },
        'Cpanel::Exception::Netlink' => sub {
            require Cpanel::Linux::Proc::Net::Udp;

            $ar = Cpanel::Linux::Proc::Net::Udp::get_udp4_sockets();
        },
    );

    return $ar;
}

#----------------------------------------------------------------------

=head2 $SOCKETS_AR = get_udp6_sockets()

Like C<get_tcp6_sockets()> but for UDP.

=cut

sub get_udp6_sockets {
    my $ar;

    Cpanel::Try::try(
        sub {
            $ar = _normalize_ip6( _get_udp_sockets_from_netlink_sock_diag( $Cpanel::Socket::Constants::AF_INET6, _IP6_INET_DIAG_MSG_TEMPLATE() ) );
        },
        'Cpanel::Exception::Netlink' => sub {
            require Cpanel::Linux::Proc::Net::Udp;

            $ar = Cpanel::Linux::Proc::Net::Udp::get_udp6_sockets();
        },
    );

    return $ar;
}

#----------------------------------------------------------------------

sub _normalize_ip4 {
    my ($sockets_ar) = @_;

    for my $s_hr (@$sockets_ar) {
        $_ = Cpanel::Socket::Micro::inet_ntoa($_) for @{$s_hr}{ 'src', 'dst' };
    }

    return $sockets_ar;
}

sub _normalize_ip6 {
    my ($sockets_ar) = @_;

    for my $s_hr (@$sockets_ar) {
        $_ = Cpanel::Socket::Micro::inet6_ntoa($_) for @{$s_hr}{ 'src', 'dst' };
    }

    return $sockets_ar;
}

# 2.6 kernels don’t implement SOCK_DIAG_BY_FAMILY, so let’s use
# TCPDIAG_GETSOCK. Unfortunately this means that we have to use
# /proc, which is much slower, to query information about UDP sockets.
sub _get_sockets_from_netlink_tcp_diag {
    my ( $sock_family, $recv_tmpl_ar ) = @_;

    my $inet_diag_req = _inet_diag_req();

    return _get_sockets_from_netlink(
        TCPDIAG_GETSOCK(),
        $inet_diag_req,
        $recv_tmpl_ar,
        {
            idiag_family => $sock_family,
        },
    );
}

sub _get_udp_sockets_from_netlink_sock_diag {
    my ( $sock_family, $recv_tmpl_ar ) = @_;

    return _get_sockets_from_netlink(
        SOCK_DIAG_BY_FAMILY(),
        _inet_diag_req_v2(),
        $recv_tmpl_ar,
        {
            sdiag_family   => $sock_family,
            sdiag_protocol => $Cpanel::Socket::Constants::PROTO_UDP,
        },
    );
}

sub _get_sockets_from_netlink {
    my ( $msg_type, $send_pack_obj, $recv_tmpl_ar, $msg_hr ) = @_;

    local $msg_hr->{'idiag_states'} = TCPF_ALL();

    my $sock = _get_netlink_socket();

    my @resps;

    Cpanel::Linux::Netlink::netlink_transaction(
        header => [
            nlmsg_type  => $msg_type,
            nlmsg_flags => $Cpanel::Linux::Netlink::NLM_F_ROOT,
        ],
        sock          => $sock,
        send_pack_obj => $send_pack_obj,
        recv_pack_obj => Cpanel::Pack->new($recv_tmpl_ar),
        message       => $msg_hr,

        # NB: This depends on an 8-byte payload after the message body.
        # It’s unclear what that actually is.
        payload_parser => sub {
            my ( $num, $msg, $bin ) = @_;
            push @resps, $msg;
        },
    );

    return \@resps;
}

# called in tests
sub _inet_diag_req {
    return Cpanel::Pack->new( \@Cpanel::Linux::Netlink::INET_DIAG_REQ_TEMPLATE );
}

# called in tests
sub _inet_diag_req_v2 {
    return Cpanel::Pack->new(
        [
            sdiag_family   => 'C',
            sdiag_protocol => 'C',
            idiag_ext      => 'C',
            idiag_states   => 'x![L] L',
            @Cpanel::Linux::Netlink::INET_DIAG_SOCKID_TEMPLATE,
        ]
    );
}

our $unsupported_kernel_touch_file = '/var/cpanel/kernel_does_not_support_modern_ipv4_socket_options';

# replaced in tests
sub _get_netlink_socket {

    my $sock;

    # CPANEL-42666: This will die on older 2.6 kernels with the message
    # 'Protocol not supported' so we need to check the kernel version and use
    # $Cpanel::Linux::Netlink::NETLINK_INET_DIAG_26_KERNEL on older C6 kernels
    my $rkv = Cpanel::Kernel::get_running_version();
    if ( $rkv =~ /^2\./a || -e $unsupported_kernel_touch_file ) {
        Cpanel::Autodie::socket( $sock, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, $Cpanel::Linux::Netlink::NETLINK_INET_DIAG_26_KERNEL );
    }
    else {
        Cpanel::Autodie::socket( $sock, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, $Cpanel::Linux::Netlink::NETLINK_INET_DIAG );
    }

    return $sock;
}

1;
