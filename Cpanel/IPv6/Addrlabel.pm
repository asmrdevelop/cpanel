package Cpanel::IPv6::Addrlabel;

# cpanel - Cpanel/IPv6/Addrlabel.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::LoadModule        ();
use Cpanel::Pack              ();
use Cpanel::Pack::Template    ();
use Cpanel::Socket::Constants ();
use Cpanel::Linux::Netlink    ();

our $VERSION = '1.04';

use constant RTM_NEWADDRLABEL => 72;
use constant RTM_DELADDRLABEL => 73;
use constant RTM_GETADDRLABEL => 74;
use constant PAGE_SIZE        => 0x400;
use constant READ_SIZE        => 8 * PAGE_SIZE;

use constant IFAL_ADDRESS => 1;
use constant IFAL_LABEL   => 2;

use constant IFLA_EXT_MASK      => 29;
use constant RTEXT_FILTER_VF    => 1;
use constant DESTINATION_KERNEL => 0;

our @ADD_REQUEST_TEMPLATE = (
    'nlmsg_length'    => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Length of message including header.
    'nlmsg_type'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Type of message content
    'nlmsg_flags'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Netlink flags
    'nlmsg_seq'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Netlink Sequence number
    'nlmsg_pid'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Recipient / Sender port ID
    'ifal_family'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # Address family
    '__ifal_reserved' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # unused
    'ifal_prefixlen'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # active bytes in the prefix
    'ifal_flags'      => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # link flags
    'ifal_index'      => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link index nubmer
    'ifal_seq'        => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link sequence number
    'label_len'       => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of label attribute
    'label_type'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of label attribute
    'label'           => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # addrlabel
    'prefix_len'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of prefix attribute
    'prefix_type'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of prefix attribute
    'prefix'          => 'a16',                                        # prefix in address format
);

our @LIST_REQUEST_TEMPLATE = (
    'nlmsg_length'    => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Length of message including header.
    'nlmsg_type'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Type of message content
    'nlmsg_flags'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Netlink flags
    'nlmsg_seq'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Netlink Sequence number
    'nlmsg_pid'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Recipient / Sender port ID
    'ifi_family'      => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # ifi_family;
    '__ifi_pad'       => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # unused
    'ifi_type'        => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # ifi_type;   /* ARPHRD_* */
    'ifi_index'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # ifi_index;    /* Link index */
    'ifi_flags'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # ifi_flags;    /* IFF_* flags  */
    'ifi_change'      => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # ifi_change;   /* IFF_* change mask */
    'rta_len'         => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # routing attribute length
    'rta_type'        => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # routing attribute type
    'ext_filter_mask' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # extended filter mask
);

our @REMOVE_REQUEST_TEMPLATE = (
    'nlmsg_length'    => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Length of message including header.
    'nlmsg_type'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Type of message content
    'nlmsg_flags'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Netlink flags
    'nlmsg_seq'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Netlink Sequence number
    'nlmsg_pid'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Recipient / Sender port ID
    'ifal_family'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # Address family
    '__ifal_reserved' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # unused
    'ifal_prefixlen'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # active bytes in the prefix
    'ifal_flags'      => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # link flags
    'ifal_index'      => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link index nubmer
    'ifal_seq'        => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link sequence number
    'label_len'       => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of label attribute
    'label_type'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of label attribute
    'label'           => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # addrlabel
    'prefix_len'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of prefix attribute
    'prefix_type'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of prefix attribute
    'prefix'          => 'a16',                                        # prefix in address format
);

our @ADDRLABEL_MESSAGE_TEMPLATE = (
    'ifal_family'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # Address family
    '__ifal_reserved' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # unused
    'ifal_prefixlen'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # active bytes in the prefix
    'ifal_flags'      => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # link flags
    'ifal_index'      => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link index nubmer
    'ifal_seq'        => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link sequence number
);

our @ATTRIBUTE_HEADER_TEMPLATE = (
    'nla_len'  => Cpanel::Pack::Template::PACK_TEMPLATE_U16,           # length of attribute
    'nla_type' => Cpanel::Pack::Template::PACK_TEMPLATE_U16,           # type of attribute (request specific)
);

*_my_socket  = *CORE::socket;
*_my_send    = *CORE::send;
*_my_sysread = *CORE::sysread;

sub add {
    my ( $prefix, $label ) = @_;

    if ( !defined $prefix ) {
        return ( 0, "\$prefix cannot be undef in calls to Cpanel::IPv6::Addrlabel::add" );
    }
    if ( !defined $label ) {
        return ( 0, "\$label cannot be undef in calls to Cpanel::IPv6::Addrlabel::add" );
    }

    Cpanel::LoadModule::load_perl_module('Socket');

    my $address;
    my $bits;
    if ( $prefix =~ m/^(.*)\/(\d+)$/ ) {
        $address = $1;
        $bits    = $2 || 128;
    }

    # historically misnamed a sequence, but only used as a response filter
    my $sequence = int( rand(1000000) );

    my $prefix_bytes = Socket::inet_pton( Socket::AF_INET6(), $address );

    my $ADD_REQUEST = Cpanel::Pack->new( \@ADD_REQUEST_TEMPLATE );
    my $add_request = $ADD_REQUEST->pack_from_hashref(
        {
            nlmsg_length   => $ADD_REQUEST->sizeof(),
            nlmsg_type     => RTM_NEWADDRLABEL,
            nlmsg_flags    => $Cpanel::Linux::Netlink::NLM_F_REQUEST | $Cpanel::Linux::Netlink::NLM_F_ACK,
            nlmsg_seq      => $sequence,
            nlmsg_pid      => 0,
            ifal_family    => $Cpanel::Socket::Constants::AF_INET6,
            ifal_prefixlen => $bits,
            ifal_flags     => 0,
            ifal_index     => 0,
            ifal_seq       => 0,

            # length(label_len, label_type, label)
            label_len  => 8,
            label_type => IFAL_LABEL,
            label      => $label,

            # length(prefix_len, prefix_type, prefix)
            prefix_len  => 20,
            prefix_type => IFAL_ADDRESS,
            prefix      => $prefix_bytes,
        }
    );

    my $NETLINK_MESSAGE = Cpanel::Pack->new( \@Cpanel::Linux::Netlink::NLMSG_HEADER_TEMPLATE );

    my $socket;
    _my_socket( $socket, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, 0 ) or return ( 0, "socket: $!" );
    _my_send( $socket, $add_request, 0 )                                                               or return ( 0, "send: $!" );

    my $error = Cpanel::Linux::Netlink::expect_acknowledgment( \&_my_sysread, $socket, $sequence );
    if ($error) {
        return ( 0, $error );
    }
    return ( 1, $prefix, $label );
}

sub list {
    my %prefixes;

    Cpanel::LoadModule::load_perl_module('Socket');

    # historically misnamed a sequence, but only used as a response filter
    my $sequence = int( rand(1000000) );

    my $LIST_REQUEST = Cpanel::Pack->new( \@LIST_REQUEST_TEMPLATE );
    my $request      = $LIST_REQUEST->pack_from_hashref(
        {
            nlmsg_length    => $LIST_REQUEST->sizeof(),
            nlmsg_type      => RTM_GETADDRLABEL(),
            nlmsg_flags     => $Cpanel::Linux::Netlink::NLM_F_ROOT | $Cpanel::Linux::Netlink::NLM_F_MATCH | $Cpanel::Linux::Netlink::NLM_F_REQUEST,
            nlmsg_seq       => $sequence,
            nlmsg_pid       => DESTINATION_KERNEL(),
            ifi_family      => $Cpanel::Socket::Constants::AF_INET6,
            rta_type        => IFLA_EXT_MASK(),
            rta_len         => 8,                                                                                                                     # size of (rta_len + rta_type + ext_filter_mask)
            ext_filter_mask => RTEXT_FILTER_VF()
        }
    );

    my $NETLINK_MESSAGE   = Cpanel::Pack->new( \@Cpanel::Linux::Netlink::NLMSG_HEADER_TEMPLATE );
    my $ADDRLABEL_MESSAGE = Cpanel::Pack->new( \@ADDRLABEL_MESSAGE_TEMPLATE );
    my $ATTRIBUTE_HEADER  = Cpanel::Pack->new( \@ATTRIBUTE_HEADER_TEMPLATE );

    my $socket;
    _my_socket( $socket, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, 0 ) or return ( 0, "socket: $!" );
    _my_send( $socket, $request, 0 )                                                                   or return ( 0, "send: $!" );

    my $response_buffer = '';
    my $header_hr;
    do {
        while ( length $response_buffer < $NETLINK_MESSAGE->sizeof() ) {
            _my_sysread( $socket, \$response_buffer, READ_SIZE(), length $response_buffer ) or return ( 0, "sysread, message header: $!" );
        }
        $header_hr = $NETLINK_MESSAGE->unpack_to_hashref( substr( $response_buffer, 0, $NETLINK_MESSAGE->sizeof() ) );

        while ( length $response_buffer < $header_hr->{nlmsg_length} ) {
            _my_sysread( $socket, \$response_buffer, READ_SIZE(), length $response_buffer ) or return ( 0, "sysread, message body: $!" );
        }

        # pulls one mesage off the repsonse buffer, note the 4th parameter which replaces the message in response_buffer with ''
        my $message = substr( $response_buffer, 0, $header_hr->{nlmsg_length}, '' );

        if ( $header_hr->{nlmsg_seq} eq $sequence ) {
            if ( $header_hr->{nlmsg_type} == RTM_NEWADDRLABEL() ) {
                my $socket_hr       = $ADDRLABEL_MESSAGE->unpack_to_hashref( substr( $message, $NETLINK_MESSAGE->sizeof(), $ADDRLABEL_MESSAGE->sizeof(), ) );
                my $attribute_index = $NETLINK_MESSAGE->sizeof() + $ADDRLABEL_MESSAGE->sizeof();

                my $prefix;
                my $label;
                while ( $attribute_index < length $message ) {
                    my $attribute = $ATTRIBUTE_HEADER->unpack_to_hashref( substr( $message, $attribute_index, $ATTRIBUTE_HEADER->sizeof() ) );
                    $attribute->{data} = substr( $message, $attribute_index + $ATTRIBUTE_HEADER->sizeof(), $attribute->{nla_len} - $ATTRIBUTE_HEADER->sizeof() );
                    $attribute_index += $attribute->{nla_len};
                    if ( $attribute->{nla_type} == IFAL_ADDRESS ) {
                        $prefix = Socket::inet_ntop( Socket::AF_INET6(), $attribute->{data} ) . "/$socket_hr->{ifal_prefixlen}";
                    }
                    elsif ( $attribute->{nla_type} == IFAL_LABEL ) {
                        $label = unpack( Cpanel::Pack::Template::PACK_TEMPLATE_U32, $attribute->{data}, );
                    }
                }
                $prefixes{$prefix} = $label;
            }
            elsif ( $header_hr->{nlmsg_type} == $Cpanel::Linux::Netlink::NLMSG_ERROR ) {
                my $error_code = unpack( Cpanel::Pack::Template::PACK_TEMPLATE_U32, substr( $message, $NETLINK_MESSAGE->sizeof(), Cpanel::Pack::Template::U32_BYTES_LENGTH ) );
                if ( $error_code == 0 ) {
                    return ( 0, "Received ACK when expecting data" );
                }
                else {
                    local $! = -$error_code;
                    return ( 0, "Received error code when expecting data: $!\n" );
                }
            }
            elsif ( $header_hr->{nlmsg_type} == $Cpanel::Linux::Netlink::NLMSG_OVERRUN ) {
                return ( 0, "Data lost due to message overrun" );
            }
        }
    } while ( $header_hr->{nlmsg_type} != $Cpanel::Linux::Netlink::NLMSG_DONE );

    return ( 1, \%prefixes );
}

sub remove {
    my ( $prefix, $label ) = @_;

    if ( !defined $prefix ) {
        return ( 0, "\$prefix cannot be undef in calls to Cpanel::IPv6::Addrlabel::remove" );
    }
    if ( !defined $label ) {
        return ( 0, "\$label cannot be undef in calls to Cpanel::IPv6::Addrlabel::remove" );
    }

    Cpanel::LoadModule::load_perl_module('Socket');

    my $address;
    my $bits;
    if ( $prefix =~ m/^(.*)\/(\d+)$/ ) {
        $address = $1;
        $bits    = $2 || 128;
    }

    # historically misnamed a sequence, but only used as a response filter
    my $sequence = int( rand(1000000) );

    my $prefix_bytes = Socket::inet_pton( Socket::AF_INET6(), $address );

    my $REMOVE_REQUEST = Cpanel::Pack->new( \@REMOVE_REQUEST_TEMPLATE );
    my $remove_request = $REMOVE_REQUEST->pack_from_hashref(
        {
            nlmsg_type     => RTM_DELADDRLABEL,
            nlmsg_flags    => $Cpanel::Linux::Netlink::NLM_F_REQUEST | $Cpanel::Linux::Netlink::NLM_F_ACK,
            nlmsg_seq      => $sequence,
            nlmsg_length   => $REMOVE_REQUEST->sizeof(),
            nlmsg_pid      => 0,
            ifal_family    => $Cpanel::Socket::Constants::AF_INET6,
            ifal_prefixlen => $bits,
            ifal_flags     => 0,
            ifal_index     => 0,
            ifal_seq       => 0,
            label_len      => 8,                                                                             # length(label_len, label_type, label)
            label_type     => IFAL_LABEL,
            label          => $label,
            prefix_len     => 20,                                                                            # length(prefix_len, prefix_type, prefix)
            prefix_type    => IFAL_ADDRESS,
            prefix         => $prefix_bytes,
        }
    );

    my $NETLINK_MESSAGE = Cpanel::Pack->new( \@Cpanel::Linux::Netlink::NLMSG_HEADER_TEMPLATE );

    my $socket;
    _my_socket( $socket, $Cpanel::Linux::Netlink::PF_NETLINK, $Cpanel::Linux::Netlink::SOCK_DGRAM, 0 ) or return ( 0, "socket: $!" );
    _my_send( $socket, $remove_request, 0 )                                                            or return ( 0, "send: $!" );

    my $error = Cpanel::Linux::Netlink::expect_acknowledgment( \&_my_sysread, $socket, $sequence );
    if ($error) {
        return ( 0, $error );
    }
    return ( 1, $prefix, $label );
}

sub search_by_prefix {
    my ($prefix) = @_;
    my ( $success, $prefix_hr ) = list();
    if ( !$success ) {
        return ( $success, $prefix_hr );
    }
    if ( exists $prefix_hr->{$prefix} ) {
        return ( $success, { $prefix, $prefix_hr->{$prefix} } );
    }
    else {
        return ( $success, {} );
    }
}

sub search_by_label {
    my ($label) = @_;
    my ( $success, $addrlabels ) = list();
    if ( !$success ) {
        return ( $success, $addrlabels );
    }
    for my $key ( keys %{$addrlabels} ) {
        if ( $addrlabels->{$key} ne $label ) {
            delete $addrlabels->{$key};
        }
    }
    return ( $success, $addrlabels );
}

1;
__END__

=pod

=head1 NAME

Cpanel::IPv6::Addrlabel - IPv6 Address Label support.

=head1 VERSION

This document refers to Cpanel::IPv6::Addrlabel version 1.04

=head1 SYNOPSIS

    # low memory access
    use Cpanel::IPv6::Addrlabel ();

    _or_

    # fast access
    use Socket                  ();
    use Cpanel::IPv6::Addrlabel ();

    my $success;
    my $prefix;
    my $label;
    my $addrlabels;

    # add an IPv6 address label
    ($success, $prefix, $label) = Cpanel::IPv6::Addlabel->add('2083::2001::/24', 99)

    # obtain all the IPv6 address labels
    ($success, $addrlabels) = Cpanel::IPv6::Addrlabel::list();

    for my $prefix (keys %{$addrlabels} ) {
       printf("prefix %s has label %d\n", $prefix, $addrlabels->{$prefix});
    }

    # remove an IPv6 address label
    ($success, $prefix, $label) = Cpanel::IPv6::Addlabel->remove('2083::2001::/24', 99);

    # obtain the IPv6 address label for a known prefix
    ($success, $addrlabels) = Cpanel::IPv6::Addrlabel::search_by_prefix('2083::2001::/24');

    # obtain the IPv6 address label for a known prefix
    ($success, $addrlabels) = Cpanel::IPv6::Addrlabel::search_by_label(99);

=head1 DESCRIPTION

Cpanel::IPv6::Addrlabel provides access to the underlying system's IPv6
Addrlabel configuration.

=head1 METHODS

=head2 B<($success, $prefix, $label) = Cpanel::IPv6::Addlabel-E<gt>remove($prefix, $label)>

Remove an IPv6 Address Label.

This initiates a communication to the kernel using the Netlink protocol.

To add an address label, the client sends a RTM_DELADDRLABEL message.

The format for the RTM_ADDADDRLABEL message is:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |  ifal_family  |_ifal_reserved |ifal_prefixlen |  ifal_flags   |
   +---------------+---------------+---------------+---------------+
14 |                          ifal_index                           |
   +---------------+---------------+---------------+---------------+
18 |                           ifal_seq                            |
   +---------------+---------------+---------------+---------------+
1C |           label_len           |           label_type          |
   +---------------+---------------+---------------+---------------+
20 |                             label                             |
   +---------------+---------------+---------------+---------------+
24 |          prefix_len           |          prefix_type          |
   +---------------+---------------+---------------+---------------+
28 |                                                               |
   +                                                               +
2C |                                                               |
   +                            prefix                             +
30 |                                                               |
   +                                                               +
34 |                                                               |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000038 (38.00.00.00) (length of whole packet)
 nlmsg_type      = 0x00000049 (48.00) RTM_ADDADDRLABEL
 nlmsg_flags     = 0x00000005 (01.03)
                   0x00000001 NLM_F_REQUEST (Request message)
                   0x00000004 NLM_F_ACK     (Request message acknolwegement)
 nlmsg_seq       = (some number, used to filter replies)
 nlmsg_pid       = 0x00000000 (kernel process port id)

 ifal_family     = 0x0000000a (0a) AF_INET6 (IPv6 family)
 ifal_prefixlen  = 0x00000040 (40) (first 64 bits, /64)
 ifal_flags      = 0x00000000 (00) (link flags)
 ifal_index      = 0x00000000 (00.00.00.00) (link index)
 ifal_seq        = 0x00000000 (00.00.00.00) (link sequence)

 label_len       = 0x00000008 (08.00) label attribute length (0x08 = 0x24 - 0x1C)
 label_type      = 0x00000002 (02.00) IFAL_LABEL (addrlabel label type)
 label           = 0x000000de (de.00.00.00) (label in hex, 222)

 prefix_len      = 0x00000014 (14.00) prefix attribute length (0x14 = 0x24
 prefix_type     = 0x00000014 (01.00) IFAL_ADDRESS (addrlabel address type)
 prefix          = 0x20010db8, 0x1a3457cf, 0x00000000, 0x00000000,
                   (20.01.0d.b8.1a.34.57.cf.00.00.00.00.00.00.00.00)
                   (ipv6 prefix, as an address)

 Which is typically replied to with a single acknowledgement message:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |                          nlmsg_error                          |
   +---------------+---------------+---------------+---------------+
14 |                          sent_length                          |
   +---------------+---------------+---------------+---------------+
18 |           sent_type           |           sent_flags          |
   +---------------+---------------+---------------+---------------+
1C |                           sent_seq                            |
   +---------------+---------------+---------------+---------------+
20 |                           sent_pid                            |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000024 (24.00.00.00)
 nlmsg_type      = 0x00000002 (02.00) NLMSG_ERROR
                   (successful acknowledgements are errors with
                    nlmsg_error set to zero)
 nlmsg_flags     = 0x00000000 (00.00)
 nlmsg_seq       = (the number sent in the request)
 nlmsg_pid       = (this application's process id)
 nlmsg_error     = 0x00000000 (00.00.00.00)
                   (must be zero, otherwise an error occurred)

 sent_length     = (the nlmsg_length in the initial request)
 sent_type       = (the nlmsg_type in the initial request)
 sent_flags      = (the nlmsg_flags in the initial request)
 sent_seq        = (the nlmsg_seq in the initial request)
 sent_pid        = (the nlmsg_pid in the initial request)

=over 4

=item B<$prefix>

The IPv6 prefix portion of the address label being added.  Note that the IPv6 must
be in canonical form, as detailed in RFC5952.  In addition the number of active bits
in the prefix should be specificed with a trailing /bits specifier.

=item B<$label>

The label portion of the address label being added.

=back

=head3 B<Returns>

=over 4

=item B<$success>

A number indicating if a the request was handled successfully.  1 indicates success,
0 indicates an error occurred.

=item B<$prefix>

When $success is 1, the prefix portion of the added address label.

When $success is 0, a string containing a description of the error.

=item B<$label>

When $success is 1, the label portion of the added address label.

When $success is 0, undef.

=back

=head2 B<($success, $addrlabels) = Cpanel::IPv6::Addrlabels-E<gt>list()>

Lists all IPv6 Address Labels.

This initiates a communication to the kernel using the Netlink protocol.

To obtain the addresses, the client sends a RTM_GETADDRLABEL message
which is typically replied to with one or more RTM_NEWADDRLABEL messages
terminated by a NLMSG_DONE message.

The format for the RTM_GETADDRLABEL message is:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |  ifi_family   |   __ifi_pad   |           ifi_type            |
   +---------------+---------------+---------------+---------------+
14 |                           ifi_index                           |
   +---------------+---------------+---------------+---------------+
18 |                           ifi_flags                           |
   +---------------+---------------+---------------+---------------+
1C |                          ifi_change                           |
   +---------------+---------------+---------------+---------------+
20 |            rta_len            |            rta_type           |
   +---------------+---------------+---------------+---------------+
24 |                         ext_filter_mask                       |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000028 (28.00.00.00) (length of whole packet)
 nlmsg_type      = 0x0000004A (4a.00) RTM_GETADDRLABEL
 nlmsg_flags     = 0x00000301 (01.03)
                   0x00000001 NLM_F_REQUEST (Request message)
                   0x00000100 NLM_F_ROOT    (Tree root request)
                   0x00000200 NLM_F_MATCH   (Return all matching)
 nlmsg_seq       = (some number, used to filter replies)
 nlmsg_pid       = 0x00000000 (kernel process port id)
 ifi_family      = 0x0000000a (0a) AF_INET6 (IPv6 family)
 ifi_type        = 0x00000000 (00.00) ARPHRD_NETROM (Any pseudo network device)
 ifi_index       = 0x00000000 (00.00.00.00) (link index)
 ifi_flags       = 0x00000000 (00.00.00.00) (no net_device_flags specificed)
 ifi_change      = 0x00000000 (00.00.00.00) (no iff change mask specified)
 rta_len         = 0x00000008 (08.00) (length of rta_len, rta_type, and ext_filter_mask in bytes)
 rta_type        = 0x0000001d (1d.00) EXTENDED_INFO_MASK
 ext_filter_mask = 0x00000001 (01.00.00.00) RTEXT_FILTER_VF (Don't return virtual functions)

 Which is then receives one or more of the RTM_NEWADDRLABEL messages:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |  ifi_family   |  __ifi_pad    |ifal_prefixlen |  ifal_flags   |
   +---------------+---------------+---------------+---------------+
14 |                          ifal_index                           |
   +---------------+---------------+---------------+---------------+
18 |                           ifal_seq                            |
   +---------------+---------------+---------------+---------------+
1C |          rta_len(14)          |          rta_type(1)          |
   +---------------+---------------+---------------+---------------+
20 |                                                               |
   |                                                               |
24 |                                                               |
   |                          rta_data(1)                          |
28 |                                                               |
   |                                                               |
2C |                                                               |
   +---------------+---------------+---------------+---------------+
30 |          rta_len(8)           |          rta_type(2)          |
   +---------------+---------------+---------------+---------------+
34 |                          rta_data(2)                          |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000038 (38.00.00.00)
 nlmsg_type      = 0x00000048 (48.00) RTM_NEWADDRLABEL (new to client, not to kernel)
 nlmsg_flags     = 0x00000002 (02.00)
                   0x00000002 NLM_F_MULTI (multi part messasge)
 nlmsg_seq       = (the number sent in the request)
 nlmsg_pid       = (this application's process id)

 ifal_family     = 0x0000000a (0a) AF_INET6 (IPv6 family)
 ifal_prefixlen  = 0x00000080 (80) (80 hex = 128 decimal)
 ifal_flags      = 0x00000000 (00) (link flags)
 ifal_index      = 0x00000000 (00.00.00.00) (link index)
 ifal_seq        = 0x000000a4 (a4.00.00.00) (link sequence)

 rta_len(14)     = 0x00000014 (14.00) (size of attribute)
 rta_type(1)     = 0x00000001 (01.00) (address attribute)
 rta_data(1)     = 0x11114222, 0x33334444, 0x55556666, 0x77778888,
                   (11.11.42.22.33.33.44.44.55.55.66.66.77.77.88.88)
                   (ipv6 address)

 rta_len(8)      = 0x00000008 (08.00) (size of attribute)
 rta_type(2)     = 0x00000002 (02.00) (label attribute)
 rta_data(2)     = 0x000008ae (ae.08.00.00) (decimal 2222)

 (note that the block of bytes documented from offset 1C to 30 and the
 block of bytes documented from offset 30 to 38 may be in reverse order)

 Terminated by one NLMSG_DONE:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000014 (14.00.00.00)
 nlmsg_type      = 0x00000003 (03.00) NLMSG_DONE (end of multipart message)
 nlmsg_flags     = 0x00000002 (02.00)
                   0x00000002 NLM_F_MULTI (multi part messasge)
 nlmsg_seq       = (the number sent in the request)
 nlmsg_pid       = (this application's process id)

 Note: While we receive than the message requires, we have no documentation
 on the purpose of the undocumented bits between 10 and 14.

=head3 B<Returns>

=over 4

=item B<$success>

A number indicating if a the request was handled successfully.  1 indicates success,
0 indicates an error occurred.

=item B<$addrlabels>

When $success is 1, a hash reference, with the entries mapping IPv6 prefixes to their
label values.  When $success is 0, a string containing a description of the error.

    $addrlabels = {
       '2083::2001::/24' =>  2222,
       '1111:2222:3333:4444:5555:66666:7777:8888/128' => 256,
       '::/1' => 32,
    };

=back

=head2 B<($success, $addrlabels) = Cpanel::IPv6::Addrlabels-E<gt>search_by_prefix($prefix)>

Lists the IPv6 Address Label for $prefix.

=over 4

=item B<$prefix>

The IPv6 prefix being searched for.  Note that the IPv6 must be in canonical form, as
detailed in RFC5952.  In addition the number of active bits in the prefix should be
specificed with a trailing /bits specifier.

=back

=head3 B<Returns>

=over 4

=item B<$success>

A number indicating if a the request was handled successfully.  1 indicates success,
0 indicates an error occurred.

=item B<$addrlabels>

When $success is 1, a hash reference, with the entry mapping IPv6 prefixes to its label
value, or a hash reference, with no entry present.
When $success is 0, a string containing a description of the error.

    # successful search, yielding a result
    $addrlabels = {
       '2083::2001::/24' =>  2222,
    };

    # successful search, yielding no results
    $addrlabels = {
    };

=back

=head2 B<($success, $addrlabels) = Cpanel::IPv6::Addrlabel-E<gt>search_by_label($label)>

Lists the IPv6 Address Labels for label $label.

=over 4

=item B<$label>

The IPv6 prefix being searched for.  Note that the IPv6 must be in canonical form, as
detailed in RFC5952.  In addition the number of active bits in the prefix should be
specificed with a trailing /bits specifier.

=back

=head3 B<Returns>

=over 4

=item B<$success>

A number indicating if a the request was handled successfully.  1 indicates success,
0 indicates an error occurred.

=item B<$addrlabels>

When $success is 1, a hash reference, with the entry mapping all IPv6 prefixes to the
requested label value, or a hash reference, with no entries present.
When $success is 0, a string containing a description of the error.

    # successful search, yielding a result
    $addrlabels = {
       '2083::2001::/24' =>  2222,
       '2083::2221:1010:/24' =>  2222,
       '3000::2001:a3:/24' =>  2222,
       '4013::3a01:b0:/24' =>  2222,
    };

    # successful search, yielding no results
    $addrlabels = {
    };

=back

=head2 B<($success, $prefix, $label) = Cpanel::IPv6::Addlabel-E<gt>remove($prefix, $label)>

Remove an IPv6 Address Label.

This initiates a communication to the kernel using the Netlink protocol.

To remove an address label, the client sends a RTM_DELADDRLABEL message.

The format for the RTM_DELADDRLABEL message is:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |  ifal_family  |_ifal_reserved |ifal_prefixlen |  ifal_flags   |
   +---------------+---------------+---------------+---------------+
14 |                          ifal_index                           |
   +---------------+---------------+---------------+---------------+
18 |                           ifal_seq                            |
   +---------------+---------------+---------------+---------------+
1C |           label_len           |           label_type          |
   +---------------+---------------+---------------+---------------+
20 |                             label                             |
   +---------------+---------------+---------------+---------------+
24 |          prefix_len           |          prefix_type          |
   +---------------+---------------+---------------+---------------+
28 |                                                               |
   +                                                               +
2C |                                                               |
   +                            prefix                             +
30 |                                                               |
   +                                                               +
34 |                                                               |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000038 (38.00.00.00) (length of whole packet)
 nlmsg_type      = 0x00000049 (49.00) RTM_DELADDRLABEL
 nlmsg_flags     = 0x00000005 (01.03)
                   0x00000001 NLM_F_REQUEST (Request message)
                   0x00000004 NLM_F_ACK     (Request message acknolwegement)
 nlmsg_seq       = (some number, used to filter replies)
 nlmsg_pid       = 0x00000000 (kernel process port id)

 ifal_family     = 0x0000000a (0a) AF_INET6 (IPv6 family)
 ifal_prefixlen  = 0x00000040 (40) (first 64 bits, /64)
 ifal_flags      = 0x00000000 (00) (link flags)
 ifal_index      = 0x00000000 (00.00.00.00) (link index)
 ifal_seq        = 0x00000000 (00.00.00.00) (link sequence)

 label_len       = 0x00000008 (08.00) label attribute length (0x08 = 0x24 - 0x1C)
 label_type      = 0x00000002 (02.00) IFAL_LABEL (addrlabel label type)
 label           = 0x000000de (de.00.00.00) (label in hex, 222)

 prefix_len      = 0x00000014 (14.00) prefix attribute length (0x14 = 0x24
 prefix_type     = 0x00000014 (01.00) IFAL_ADDRESS (addrlabel address type)
 prefix          = 0x20010db8, 0x1a3457cf, 0x00000000, 0x00000000,
                   (20.01.0d.b8.1a.34.57.cf.00.00.00.00.00.00.00.00)
                   (ipv6 prefix, as an address)

 Which is typically replied to with a single acknowledgement message:

    0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7 0 1 2 3 4 5 6 7
   +---------------+---------------+---------------+---------------+
00 |                         nlmsg_length                          |
   +---------------+---------------+---------------+---------------+
04 |          nlmsg_type           |          nlmsg_flags          |
   +---------------+---------------+---------------+---------------+
08 |                           nlmsg_seq                           |
   +---------------+---------------+---------------+---------------+
0C |                           nlmsg_pid                           |
   +---------------+---------------+---------------+---------------+
10 |                          nlmsg_error                          |
   +---------------+---------------+---------------+---------------+
14 |                          sent_length                          |
   +---------------+---------------+---------------+---------------+
18 |           sent_type           |           sent_flags          |
   +---------------+---------------+---------------+---------------+
1C |                           sent_seq                            |
   +---------------+---------------+---------------+---------------+
20 |                           sent_pid                            |
   +---------------+---------------+---------------+---------------+

 nlmsg_length    = 0x00000024 (24.00.00.00)
 nlmsg_type      = 0x00000002 (02.00) NLMSG_ERROR
                   (successful acknowledgements are errors with
                    nlmsg_error set to zero)
 nlmsg_flags     = 0x00000000 (00.00)
 nlmsg_seq       = (the number sent in the request)
 nlmsg_pid       = (this application's process id)
 nlmsg_error     = 0x00000000 (00.00.00.00)
                   (must be zero, otherwise an error occurred)

 sent_length     = (the nlmsg_length in the initial request)
 sent_type       = (the nlmsg_type in the initial request)
 sent_flags      = (the nlmsg_flags in the initial request)
 sent_seq        = (the nlmsg_seq in the initial request)
 sent_pid        = (the nlmsg_pid in the initial request)

=over 4

=item B<$prefix>

The IPv6 prefix portion of the address label being removed.  Note that the IPv6 must
be in canonical form, as detailed in RFC5952.  In addition the number of active bits
in the prefix should be specificed with a trailing /bits specifier.

=item B<$label>

The label portion of the address label being removed.

=back

=head3 B<Returns>

=over 4

=item B<$success>

A number indicating if a the request was handled successfully.  1 indicates success,
0 indicates an error occurred.

=item B<$prefix>

When $success is 1, the prefix portion of the removed address label.

When $success is 0, a string containing a description of the error.

=item B<$label>

When $success is 1, the label portion of the removed address label.

When $success is 0, undef.

=back

=head1 DIAGNOSTICS

=over 4

=item B<socket: ...>

The request failed to open a Netlink socket.  The available details are encoded
within the diagnostic message.

=item B<send: ...>

The request failed to send data through the Netlink socket.  The available details
are encoded within the diagnostic message.

=item B<sysread: ...>

The request failed to read data from the Netlink socket.  The available details
are encoded within the diagnostic message.

=item B<Received Error code when expecting data: ...>

The response indicates that the request could not be honored.  The exact error
was passed to the netlink client through the netlink protocol.

=item B<Data lost due to message overrun>

In response preparation, the kernel is notifying us that its Netlink response buffers
were overrun before they could be send through the Netlink socket.  The request was
honored, but return data for the request was lost.

=item B<Received ACK when expecting data>

The response to a request acknowledged the request, but the communication flow
expected returned data, not a simple acknowledgment.

=back

=head1 CONFIGURATION AND ENVIRONMENT

This module requires a Linux operating system with IPv6 enabled.

=head1 DEPENDENCIES

This module uses:

=over 8

=item Socket

Used for IPv6 formatting.

=item Cpanel::Pack

Used as syntactic sugar to improve readability of pack and unpack operations.

=item Cpanel::Pack::Template

Used to defined the Cpanel::Pack templates.

=item Cpanel::Socket::Constants

Used to access the AF_INET6 constant which specifies an IPv6 request.

=item Cpanel::Linux::Netlink

Used to access the various Netlink constants and flags.

=back

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

Currently the filtering of reponse messages does not properly filter input by
port id.  Netlink currently shifts port ids on a per socket basis, allowing
unique ids for multiple ports into a process.  This means that the port id is
partially a component of the process id, and partially a component of an algorithm
that is aware of prior port connections.  Currently we do not emulate that
routine in our code to predict the port id we should used, and for legacy
reasons, the initial response is the process id regardless of the calculated
port id.

Prefix searching does not support wild cards, and should not.  Two IPv6
prefixes with different bit patterns are fundamentally different prefixes
and one is not a sub representation of the other.  If you require wild card
searching, please use the B<list()> sub and perform your searching outside
of this module.
