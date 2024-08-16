package Cpanel::Linux::RtNetlink;

# cpanel - Cpanel/Linux/RtNetlink.pm               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

=pod

=encoding utf-8

=head1 NAME

Cpanel::Linux::RtNetlink - access to Linux’s routing data

=head1 SYNOPSIS

    use Cpanel::Linux::RtNetlink ();

    my $dev_addrs_hr = Cpanel::Linux::RtNetlink::get_addresses_by_interface('AF_INET');

=head1 DISCUSSION

Like C::L::Netlink, this module more or less assumes that you are
familiar with the protocol--which, in this case is RTNetlink, a protocol
that sits on top of Netlink.

Consult C<Cpanel::Linux::Netlink> for a “birds-eye” discussion of the protocol
and cPanel’s client implementation.

=head1 ONE-LINERS

=over

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_first_interface_and_address('AF_INET6'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_first_interface_and_address('AF_INET'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_addresses_by_interface('AF_INET6'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_addresses_by_interface('AF_INET'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_interface_addresses('AF_INET6'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_interface_addresses('AF_INET'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_interfaces('AF_INET6'));'

=item perl -MCpanel::Linux::RtNetlink -MData::Dumper -e 'print Dumper(Cpanel::Linux::RtNetlink::get_interfaces('AF_INET'));'

=back

=cut

use cPstrict;

use Cpanel::Linux::Netlink          ();
use Cpanel::Linux::NetlinkConstants ();
use Cpanel::Pack                    ();
use Cpanel::Pack::Template          ();
use Cpanel::Socket::Constants       ();

use Socket qw(inet_pton inet_ntop);

use constant {
    IFLA_IFNAME       => 4,
    DEBUG             => 0,
    AF_INET6          => $Cpanel::Linux::Netlink::AF_INET6,
    IFA_LOCAL         => Cpanel::Linux::NetlinkConstants::IFA_LOCAL(),
    IFA_ADDRESS       => Cpanel::Linux::NetlinkConstants::IFA_ADDRESS(),
    IFA_CACHEINFO     => Cpanel::Linux::NetlinkConstants::IFA_CACHEINFO(),
    IFA_LABEL         => Cpanel::Linux::NetlinkConstants::IFA_LABEL(),
    PACK_TEMPLATE_U16 => Cpanel::Pack::Template::PACK_TEMPLATE_U16,
    U16_BYTES_LENGTH  => Cpanel::Pack::Template::U16_BYTES_LENGTH,
    RTA_DST           => Cpanel::Linux::NetlinkConstants::RTA_DST(),
    RTA_PREFSRC       => Cpanel::Linux::NetlinkConstants::RTA_PREFSRC(),
};

my $INFINITY_LIFE_TIME = 4294967295;

my $NETLINK_ROUTE_SOCKET = 0;

my $PF_NETLINK = 16;

# Cache for compiled IFINFOMSG_TEMPLATE
my $IFINFOMSG_PACK_OBJ;

# Cache for compiled IFA_CACHEINFO_TEMPLATE
my $IFA_CACHEINFO_PACK_OBJ;

# Cache for compiled IFADDRMSG_TEMPLATE
my $IFADDRMSG_PACK_OBJ;

# Cache for compiled RTMSG_TEMPLATE
my $RTMSG_PACK_OBJ;

=head2 get_first_interface_and_address()

=head3 Purpose

Find the first interface id and first address
on the system not using a reserved IP.

=head3 Arguments

  $address_family - $Cpanel::Linux::Netlink::AF_INET6 or $Cpanel::Linux::Netlink::AF_INET

=head3 Output

  Returns an array of: interface, ip
  (
  0,
  '1610:0000:22a0:1107:aa1f:22ff:aec9:09d7'
  )

=cut

sub get_first_interface_and_address {
    my ($address_family) = @_;

    die "List context only!" if !wantarray;

    $address_family = _address_family_string_to_number($address_family);
    my $socket    = _make_netlink_socket();
    my $addresses = _get_interface_addresses( $socket, $address_family );

    my @fallback;
    foreach my $address ( sort { $a->{'scope'} <=> $b->{'scope'} } @{$addresses} ) {    # Prefer the largest global scope
        $address->{'ip'} ||= _unpack_address_to_ip( $address->{'address'} || '' );
        my @candidate = ( $address->{'ifindex'}, $address->{'ip'} );

        # note: the index only points back to one interface and is not good enough when using virtual IPs
        #       all virtual IPs would point back to the same interface
        #       we are adding the virtual interface name
        if ( defined $address->{label} && index( $address->{label}, ':' ) > 0 ) {    # do nothing if at position 0
            my ( $interface, $virtual ) = split( ':', $address->{label}, 2 );
            $candidate[0] .= ':' . $virtual;
        }

        @fallback = @candidate unless scalar @fallback;
        next if is_reserved_ipv4( $address->{'ip'} );

        return @candidate;
    }

    return @fallback;
}

=head2 is_reserved_ipv4()

=head3 Purpose

Check if the IP is a reserved IPv4 one.
Do not check all IP ranges but the most common ones and used by our customers

=head3 Arguments

 $ip - one IPv4 address formatted as a string

=head3 Output

  Returns a boolean, true when the IP is reserved, false otherwise.

=cut

sub is_reserved_ipv4 ($ip) {

    return unless defined $ip;

    return 1 if index( $ip, '127.' ) == 0    # 127.0.0.0/8
      || index( $ip, '10.' ) == 0            # 10.0.0.0/8
      || index( $ip, '11.' ) == 0            # 11.0.0.0/8
      || index( $ip, '192.168.' ) == 0       # 192.168.0.0/16
      ;

    if ( index( $ip, '172.' ) == 0 || index( $ip, '2' ) == 0 ) {
        if ( $ip =~ qr{^([0-9]+)\.([0-9]+)\.[0-9]+\.[0-9]+$} ) {
            return 1 if $1 == 172 && ( 16 <= $2 && $2 <= 31 );    # 172.16.0.0/12
            return 1 if $1 >= 224;                                # 224.0.0.0/4 & 240.0.0.0/4 & 255.255.255.255/32
        }
    }

    return;
}

=head2 is_reserved_ipv6($ip)

Check if the IP address is reserved for IPv6

=cut

sub is_reserved_ipv6 ($ip) {

    return unless defined $ip;

    return 1 if $ip eq '::1';
    $ip = lc $ip;
    return 1 if index( $ip, 'fe80:' ) == 0;

    return;
}

=head2 get_addresses_by_interface()

=head3 Purpose

Return a data structure in the format required
by Cpanel::IPv6::Utils::get_bound_ipv6_addresses

=head3 Arguments

  $address_family - $Cpanel::Linux::Netlink::AF_INET6 or $Cpanel::Linux::Netlink::AF_INET

=head3 Output

  Returns data structure like the following:
    {
      'em1' => {
                 '1' => {
                          'ifindex' => 2,
                          'ip' => '1610:0000:22a0:1107:aa1f:22ff:aec9:09d7',
                          'cacheinfo' => {
                                           'tstamp' => 2483191122,
                                           'cstamp' => 70902683,
                                           'ifa_prefered' => 604709,
                                           'ifa_valid' => 2591909
                                         },
                          'temporary' => 1,
                          'prefix' => 64,
                          'scope' => 0
                        },
                  ...
               },
        ...
    }

=cut

sub get_addresses_by_interface ($address_family) {

    $address_family = _address_family_string_to_number($address_family);
    my $socket     = _make_netlink_socket();
    my $addresses  = _get_interface_addresses( $socket, $address_family, { 'ip' => 1 } );
    my $interfaces = _get_interfaces( $socket, $address_family );

    my %ifcount;
    my %combined;
    foreach my $address ( @{$addresses} ) {
        next if $address->{'scope'} != Cpanel::Linux::NetlinkConstants::RT_SCOPE_UNIVERSE();    # only want global
        my $if = $interfaces->[ $address->{'ifindex'} - 1 ];
        $combined{$if}{ ++$ifcount{$if} } = $address;
    }
    return \%combined;
}

=head2 get_interfaces()

=head3 Purpose

Return an arrayref of interfaces ordered by ifindex

=head3 Arguments

  $address_family - $Cpanel::Linux::Netlink::AF_INET6 or $Cpanel::Linux::Netlink::AF_INET

=head3 Output

  An array ref like the following:

    [
      'lo',
      'em1',
      'em2'
    ]

=cut

sub get_interfaces {
    my ($address_family) = @_;
    $address_family = _address_family_string_to_number($address_family);
    return _get_interfaces( _make_netlink_socket(), $address_family );
}

=head2 get_interface_addresses()

=head3 Purpose

Return an arrayref of IP addresses ordered by ifindex

=head3 Arguments

  $address_family - $Cpanel::Linux::Netlink::AF_INET6 or $Cpanel::Linux::Netlink::AF_INET

=head3 Output

  A data structure like the following for AF_INET6:

          [
            {
              'ifindex' => 1,
              'ip' => '0000:0000:0000:0000:0000:0000:0000:0001',
              'type' => 0,
              'cacheinfo' => {
                               'tstamp' => 686,
                               'cstamp' => 686,
                               'ifa_prefered' => 4294967295,
                               'ifa_valid' => 4294967295
                             },
              'prefix' => 128,
              'scope' => 254
            },
            {
              'ifindex' => 2,
              'ip' => '1610:0000:22a0:1107:aa1f:22ff:aec9:09d7',
              'cacheinfo' => {
                               'tstamp' => 2483253527,
                               'cstamp' => 70902683,
                               'ifa_prefered' => 604748,
                               'ifa_valid' => 2591948
                             },
              'temporary' => 1,
              'prefix' => 64,
              'scope' => 0
            },
            ....
          ]

  A data structure like the following for AF_INET:

          [
            {
              'ifindex' => 1,
              'ip' => '127.0.0.1',
              'label' => 'lo',
              'prefix' => 8,
              'scope' => 254
            },
            {
              'ifindex' => 2,
              'ip' => '10.215.215.232',
              'label' => 'em1',
              'prefix' => 16,
              'scope' => 0
            },
            {
              'ifindex' => 2,
              'ip' => '198.18.115.206',
              'label' => 'em1:cp1',
              'prefix' => 24,
              'scope' => 0
            },
            ....
          ]

=cut

sub get_interface_addresses ($address_family) {
    $address_family = _address_family_string_to_number($address_family);
    return _get_interface_addresses( _make_netlink_socket(), $address_family, { 'ip' => 1 } );
}

sub _get_interfaces ( $sock, $address_family ) {

    my @interfaces;
    $IFINFOMSG_PACK_OBJ ||= Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFINFOMSG_TEMPLATE );
    Cpanel::Linux::Netlink::netlink_transaction(
        'header' => [
            'nlmsg_flags' => $Cpanel::Linux::Netlink::NLM_F_ROOT | $Cpanel::Linux::Netlink::NLM_F_MATCH,
            'nlmsg_type'  => Cpanel::Linux::NetlinkConstants::RTM_GETLINK(),
        ],
        'message' => {
            'ifi_family' => $address_family,
        },
        'sock'           => $sock,
        'send_pack_obj'  => $IFINFOMSG_PACK_OBJ,
        'recv_pack_obj'  => $IFINFOMSG_PACK_OBJ,
        'payload_parser' => _make_payload_parser(
            sub {
                my ( $nl_msgcount, $nl_response_hr, $rta_type, $value ) = @_;

                print STDERR "toto-[$nl_msgcount]\ntype:[$rta_type]==value:[$value]\n" if DEBUG;

                if ( $rta_type == Cpanel::Linux::NetlinkConstants::IFA_LABEL() ) {
                    $interfaces[ $nl_response_hr->{'ifi_index'} - 1 ] = $value =~ tr{\0}{}dr;
                }
                elsif (DEBUG) {
                    warn "Unknown rta_type: [$rta_type]";
                }
            },
        ),
    );

    return \@interfaces;
}

=head2 get_route_to()

=head3 Purpose

Use the RTM_GETROUTE message type to query the kernel about how it plans to route messages to a particular destination address.

=head3 Arguments

  $address_family - $Cpanel::Linux::Netlink::AF_INET6 or $Cpanel::Linux::Netlink::AF_INET
  $address        - A string representation of an IPv4 or IPv6 address.

=head3 Output

  An arrayref of hashrefs containing the rtnetlink attributes returned in response to the
  query. Recognized attribute types have their names translated into string
  keys and their values unpacked into appropriate native Perl types. Currently,
  only attribute types 1 (RTA_DST) and 7 (RTA_PREFSRC) are treated this way; other attributes
  have stringified integer keys and packed binary values.

  Example:

  [ {
      '15'               => "\xfe\x00\x00\x00",
      'rta_dst'          => '208.74.121.106',
      '4'                => "\x02\x00\x00\x00",
      'rta_prefsrc'      => '172.16.1.13',
      '5'                => "\xac\x10\x01\x01"
  } ]

=cut

sub get_route_to ( $address_family, $dst_ip ) {
    $address_family = _address_family_string_to_number($address_family);
    $dst_ip         = Socket::inet_pton $address_family, $dst_ip;
    return _get_route_to( _make_netlink_socket(), $address_family, $dst_ip );
}

my @RTATTR_DATA = (
    undef,
    {
        'name'    => 'rta_dst',
        'handler' => \&_rtattr_address_handler,
    },
    undef,
    undef,
    undef,
    undef,
    undef,
    {
        'name'    => 'rta_prefsrc',
        'handler' => \&_rtattr_address_handler,
    },
);

sub _rtattr_address_handler ( $value, $address_family ) {

    return Socket::inet_ntop( $address_family, $value );
}

sub _get_route_to ( $sock, $address_family, $dst_ip_packed ) {    ## no critic qw(ProhibitManyArgs)

    my ( $address_length, @attributes );

    $address_length = ( $address_family == AF_INET6 ) ? 16 : 4;

    $RTMSG_PACK_OBJ ||= Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::RTMSG_TEMPLATE );

    # This can't be cached between calls, because it could be IPv4 or IPv6:
    my $RTMSG_WITH_DST_PACK_OBJ = Cpanel::Pack->new(
        [
            @Cpanel::Linux::NetlinkConstants::RTMSG_TEMPLATE,
            @Cpanel::Linux::NetlinkConstants::RTATTR_HEADER_TEMPLATE,
            'rta_dst' => 'a' . $address_length,
        ]
    );
    Cpanel::Linux::Netlink::netlink_transaction(
        'header' => [
            'nlmsg_type' => Cpanel::Linux::NetlinkConstants::RTM_GETROUTE(),
            'nlmsg_seq'  => 1,                                                 #seems unnecessary??
        ],
        'message' => {
            'rtm_family'  => $address_family,
            'rtm_dst_len' => $address_length * 8,                              # /32 for v4, /128 for v6
            'rta_len'     => 4 + $address_length,                              # includes rtattr header size (4 bytes)
            'rta_type'    => RTA_DST,
            'rta_dst'     => $dst_ip_packed,
        },
        'sock'           => $sock,
        'send_pack_obj'  => $RTMSG_WITH_DST_PACK_OBJ,
        'recv_pack_obj'  => $RTMSG_PACK_OBJ,
        'payload_parser' => _make_payload_parser(
            sub {
                my ( $msgcount, $response_ref, $rta_type, $value ) = @_;

                $attributes[$msgcount] = {} unless defined $attributes[$msgcount];

                if ( defined $RTATTR_DATA[$rta_type] ) {
                    my $rtattr_hr = $RTATTR_DATA[$rta_type];
                    $attributes[$msgcount]->{ $rtattr_hr->{'name'} } = $rtattr_hr->{'handler'}->( $value, $address_family );
                }
                else {
                    $attributes[$msgcount]->{$rta_type} = $value;
                }
            },
        ),
    );

    return \@attributes;
}

my %_u16_cache;

#This creates a 'payload_parser' for C::L::Netlink::netlink_transaction().
sub _make_payload_parser ($for_each_rtmsg_cr) {

    return sub {
        my ( $nl_msgcount, $nlresponse_hr, $payload_sr ) = ( $_[0], $_[1], \$_[2] );
        my ( $u16, $rta_length, $rta_type, $value );
      RTATTR_LOOP:
        while ( length $$payload_sr ) {

            # Parse RTNetlink Messages
            $u16        = substr( $$payload_sr, 0, U16_BYTES_LENGTH, '' );
            $rta_length = ( $_u16_cache{$u16} //= unpack( PACK_TEMPLATE_U16, $u16 ) ) or last RTATTR_LOOP;    # unsigned short  rta_len;
            $u16        = substr( $$payload_sr, 0, U16_BYTES_LENGTH, '' );
            $rta_type   = ( $_u16_cache{$u16} //= unpack( PACK_TEMPLATE_U16, $u16 ) );
            $value      = substr( $$payload_sr, 0, $rta_length - ( U16_BYTES_LENGTH * 2 ), '' );

            # Parse RTNetlink Messages
            $for_each_rtmsg_cr->(
                $nl_msgcount,
                $nlresponse_hr,
                $rta_type,
                $value
            );
        }
    };
}

sub _get_interface_addresses ( $sock, $address_family, $want = undef ) {
    $want //= {};

    my $want_ip = $want->{'ip'};

    my @addresses;
    $IFADDRMSG_PACK_OBJ     ||= Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFADDRMSG_TEMPLATE );
    $IFA_CACHEINFO_PACK_OBJ ||= Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFA_CACHEINFO_TEMPLATE );
    Cpanel::Linux::Netlink::netlink_transaction(
        'header' => [
            'nlmsg_type'  => Cpanel::Linux::NetlinkConstants::RTM_GETADDR(),
            'nlmsg_flags' => $Cpanel::Linux::Netlink::NLM_F_ROOT,
            'nlmsg_seq'   => 1,                                                #seems unnecessary??
        ],
        'message' => {
            'ifa_family' => $address_family,
        },
        'sock'           => $sock,
        'send_pack_obj'  => $IFADDRMSG_PACK_OBJ,
        'recv_pack_obj'  => $IFADDRMSG_PACK_OBJ,
        'payload_parser' => _make_payload_parser(
            sub {
                my ( $msgcount, $response_ref, $rta_type, $value ) = @_;

                print STDERR "haha-[$msgcount]\n[$rta_type]==[$value]\n" if DEBUG;
                if ( $rta_type == IFA_LOCAL || ( $rta_type == IFA_ADDRESS && !$addresses[$msgcount]->{'ip'} ) ) {
                    @{ $addresses[$msgcount] }{ 'scope', 'ifindex', 'prefix' } = @{$response_ref}{ 'ifa_scope', 'ifa_index', 'ifa_prefixlen' };
                    if ($want_ip) {
                        $addresses[$msgcount]->{'ip'} = ( $address_family == AF_INET6 ) ? join( ":", unpack( "H4H4H4H4H4H4H4H4", $value ) ) : join( '.', unpack( 'C4', $value ) );
                    }
                    else {
                        $addresses[$msgcount]->{'address'} = $value;
                    }
                    print STDERR "[address][$addresses[$msgcount]->{'ip'}]\n" if DEBUG;
                }
                elsif ( $rta_type == IFA_CACHEINFO ) {
                    $addresses[$msgcount]->{'cacheinfo'} = $IFA_CACHEINFO_PACK_OBJ->unpack_to_hashref($value);
                    if ( $addresses[$msgcount]->{'cacheinfo'}{'ifa_valid'} == $INFINITY_LIFE_TIME ) {
                        $addresses[$msgcount]->{'type'} = 0;
                    }
                    else {
                        $addresses[$msgcount]->{'temporary'} = 1;
                    }
                }
                elsif ( $rta_type == IFA_LABEL ) {
                    $addresses[$msgcount]->{'label'} = $value =~ tr{\0}{}dr;
                }
                elsif (DEBUG) {
                    warn "Unknown rta_type: [$rta_type]";
                }
            },
        ),
    );

    return \@addresses;
}

sub _make_netlink_socket() {
    my $sock;
    socket( $sock, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, $NETLINK_ROUTE_SOCKET ) or die "socket: $!";
    return $sock;
}

my @ALLOWED_FAMILIES = qw(
  AF_INET
  AF_INET6
);

sub _address_family_string_to_number ($addr_fam) {

    if ( !grep { $_ eq $addr_fam } @ALLOWED_FAMILIES ) {
        die "“$addr_fam” is not a recognized address family; must be one of: @ALLOWED_FAMILIES";
    }

    return ${ *{ $Cpanel::Socket::Constants::{$addr_fam} }{'SCALAR'} };
}

sub _unpack_address_to_ip ($ip) {
    return length $ip > 10 ? join( ":", unpack( "H4H4H4H4H4H4H4H4", $ip ) ) : join( '.', unpack( 'C4', $ip ) );
}
1;
