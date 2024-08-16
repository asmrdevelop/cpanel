package Cpanel::Ips::V6;

# cpanel - Cpanel/Ips/V6.pm                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Pack                 ();
use Cpanel::IPv6::Has            ();
use Cpanel::Pack::Template       ();
use Cpanel::Validate::IP::Expand ();

sub fetchipv6list {
    my @addresses;

    if ( Cpanel::IPv6::Has::system_has_ipv6() ) {
        require Cpanel::Linux::Netlink;
        require Cpanel::Linux::NetlinkConstants;
        require Socket;

        my $payload_parser = sub {
            my ( $nl_msgcount, $nlresponse_hr, $payload_sr ) = ( $_[0], $_[1], \$_[2] );

            while ( length $$payload_sr ) {
                my $rta_length = unpack(
                    Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # unsigned short  rta_len
                    substr( $$payload_sr, 0, Cpanel::Pack::Template::U16_BYTES_LENGTH, '' ),
                );

                last if !$rta_length;                             # unsigned short  rta_len;

                next if ( $nlresponse_hr->{ifa_scope} != Cpanel::Linux::NetlinkConstants::RT_SCOPE_UNIVERSE() );

                my ( $rta_type, $value ) = unpack( 'S a*', substr( $$payload_sr, 0, $rta_length - Cpanel::Pack::Template::U16_BYTES_LENGTH, '' ), );

                if ( $rta_type == Cpanel::Linux::NetlinkConstants::IFA_LOCAL() || $rta_type == Cpanel::Linux::NetlinkConstants::IFA_ADDRESS() ) {
                    push @addresses, Socket::inet_ntop( Socket::AF_INET6(), $value );
                }
            }
        };
        my $socket;
        socket( $socket, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, 0 ) or die "socket: $!";

        my $IFADDRMSG_PACK_OBJ = Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFADDRMSG_TEMPLATE );
        Cpanel::Linux::Netlink::netlink_transaction(
            'header' => [
                'nlmsg_type'  => Cpanel::Linux::NetlinkConstants::RTM_GETADDR(),
                'nlmsg_flags' => $Cpanel::Linux::Netlink::NLM_F_ROOT,
                'nlmsg_seq'   => 1,                                                # First in app sequence
            ],
            'message' => {
                'ifa_family' => Socket::AF_INET6(),
            },
            'sock'           => $socket,
            'send_pack_obj'  => $IFADDRMSG_PACK_OBJ,
            'recv_pack_obj'  => $IFADDRMSG_PACK_OBJ,
            'payload_parser' => $payload_parser,
        );
    }

    return @addresses;
}

sub get_ipv6_cidr {
    my $p_ipv6 = shift;
    return if !$p_ipv6;

    # find cidr by enumerating global addresses and matching ips #
    require Cpanel::SafeRun::Object;
    my $sysips         = Cpanel::SafeRun::Object->new_or_die( 'program' => '/sbin/ip', 'args' => [qw{ -6 addr ls scope global }] )->stdout();
    my %cidrmap        = ( $sysips =~ m/inet6 ([0-9a-f:]+)\/(\d+)/g );
    my $ipv6_flattened = Cpanel::Validate::IP::Expand::expand_ipv6($p_ipv6);
    foreach my $ip ( keys %cidrmap ) {
        return $cidrmap{$ip} if Cpanel::Validate::IP::Expand::expand_ipv6($ip) eq $ipv6_flattened;
    }
    return;
}

sub validate_ipv6 {
    my ($ip) = @_;

    return if !length $ip || $ip =~ tr{0-9a-fA-F:}{}c;

    # make sure we have acceptable characters #
    #   note: we're not validating local link scopes here #
    #   note: we're not accepting ipv4 mapped addresses either, we want ipv6 addresses, not ipv4 targets #
    my $expanded_ip = Cpanel::Validate::IP::Expand::expand_ipv6($ip);

    return if !$expanded_ip;

    # now expand and then compress to get into a normalized representation #
    # NOTE: returning the modified input keeps the same behavior as the v4 validator #
    return Cpanel::Validate::IP::Expand::normalize_ipv6($expanded_ip);

}

1;
