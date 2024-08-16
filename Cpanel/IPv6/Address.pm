package Cpanel::IPv6::Address;

# cpanel - Cpanel/IPv6/Address.pm                  Copyright 2022 cPanel, L.L.C.
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
use IO::Interface::Simple     ();

our $VERSION = '1.04';

use constant RTM_NEWADDR => 20;
use constant RTM_DELADDR => 21;
use constant RTM_GETADDR => 22;
use constant PAGE_SIZE   => 0x400;
use constant READ_SIZE   => 8 * PAGE_SIZE;

use constant IFA_ADDRESS => 1;
use constant IFA_LOCAL   => 2;

use constant RT_SCOPE_UNIVERSE => 0;

use constant IFLA_EXT_MASK      => 29;
use constant RTEXT_FILTER_VF    => 1;
use constant DESTINATION_KERNEL => 0;

our @ADD_REQUEST_TEMPLATE = (
    'nlmsg_length'  => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Length of message including header.
    'nlmsg_type'    => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Type of message content
    'nlmsg_flags'   => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # Netlink flags
    'nlmsg_seq'     => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Netlink Sequence number
    'nlmsg_pid'     => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # Recipient / Sender port ID
    'ifa_family'    => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # Address family
    'ifa_prefixlen' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # active bytes in the prefix
    'ifa_flags'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # link flags
    'ifa_scope'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # address scope
    'ifa_index'     => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # link index nubmer
    'local_len'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of local attribute
    'local_type'    => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of local attribute
    'local'         => 'a16',                                        # local address
    'address_len'   => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of address attribute
    'address_type'  => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of address attribute
    'address'       => 'a16',                                        # address
);

*_my_socket  = *CORE::socket;
*_my_send    = *CORE::send;
*_my_sysread = *CORE::sysread;

sub add {
    my ( $prefix, $device ) = @_;

    if ( !defined $prefix ) {
        return ( 0, "\$prefix cannot be undef in calls to Cpanel::IPv6::Address::add" );
    }
    if ( !defined $device ) {
        return ( 0, "\$device cannot be undef in calls to Cpanel::IPv6::Address::add" );
    }
    my $interface = IO::Interface::Simple->new($device);
    if ( !$interface ) {
        return ( 0, "$device not a valid network interface" );
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
            nlmsg_length  => $ADD_REQUEST->sizeof(),
            nlmsg_type    => RTM_NEWADDR,
            nlmsg_flags   => $Cpanel::Linux::Netlink::NLM_F_REQUEST | $Cpanel::Linux::Netlink::NLM_F_ACK | $Cpanel::Linux::Netlink::NLM_F_EXCL | $Cpanel::Linux::Netlink::NLM_F_CREATE,
            nlmsg_seq     => $sequence,
            nlmsg_pid     => 0,
            ifa_family    => $Cpanel::Socket::Constants::AF_INET6,
            ifa_prefixlen => $bits,
            ifa_flags     => 0,
            ifa_scope     => RT_SCOPE_UNIVERSE,
            ifa_index     => $interface->index(),

            # length(prefix_len, prefix_type, prefix)
            local_len  => 20,
            local_type => IFA_LOCAL,
            local      => $prefix_bytes,

            address_len  => 20,
            address_type => IFA_ADDRESS,
            address      => $prefix_bytes,
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
    return ( 1, $prefix, $device );
}

1;
__END__

=pod

=head1 NAME

Cpanel::IPv6::Address - IPv6 Address support.

=head1 VERSION

This document refers to Cpanel::IPv6::Address version 1.04

=head1 SYNOPSIS

    # low memory access
    use Cpanel::IPv6::Address ();

    _or_

    # fast access
    use Socket                ();
    use Cpanel::IPv6::Address ();

    # add an IPv6 address
    my ($success, $address, $device) = Cpanel::IPv6::Addlabel->add($prefix, $device)

=head1 DESCRIPTION

Cpanel::IPv6::Address provides access to the underlying system's IPv6
Address configuration.

=head1 METHODS

=head2 B<($success, $prefix, $device) = Cpanel::IPv6::Address-E<gt>add($prefix, $device)>

Remove an IPv6 Address Label.

This initiates a communication to the kernel using the Netlink protocol.

To add an address, the client sends a RTM_NEWADDR message.

The format for the RTM_NEWADDR message is:

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
10 |   ifa_family  | ifa_prefixlen |   ifa_flags   |   ifa_scope   |
   +---------------+---------------+---------------+---------------+
14 |                           ifa_index                           |
   +---------------+---------------+---------------+---------------+
18 |           local_len           |           local_type          |
   +---------------+---------------+---------------+---------------+
1C |                                                               |
   +                                                               +
20 |                                                               |
   +                             local                             +
24 |                                                               |
   +                                                               +
28 |                                                               |
   +---------------+---------------+---------------+---------------+
2C |          address_len          |          address_type         |
   +---------------+---------------+---------------+---------------+
30 |                                                               |
   +                                                               +
34 |                                                               |
   +                            address                            +
38 |                                                               |
   +                                                               +
3C |                                                               |
   +---------------+---------------+---------------+---------------+

    'ifa_family'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      # Address family
    'ifa_prefixlen'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      # active bytes in the prefix
    'ifa_flags'      => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      # link flags
    'ifa_scope'       => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     # address scope
    'ifa_index'      => Cpanel::Pack::Template::PACK_TEMPLATE_U32,     # link index nubmer
    'local_len'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,     # length of local attribute
    'local_type'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,     # type of local attribute
    'local'          => 'a16',                                          # local address
    'address_len'      => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # length of address attribute
    'address_type'     => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    # type of address attribute
    'address'          => 'a16',                                         # address
);
 nlmsg_length    = 0x00000038 (38.00.00.00) (length of whole packet)
 nlmsg_type      = 0x00000049 (48.00) RTM_ADDADDRLABEL
 nlmsg_flags     = 0x00000005 (01.03)
                   0x00000001 NLM_F_REQUEST (Request message)
                   0x00000004 NLM_F_ACK     (Request message acknolwegement)
 nlmsg_seq       = (some number, used to filter replies)
 nlmsg_pid       = 0x00000000 (kernel process port id)

 ifa_family      = 0x0000000a (0a) AF_INET6 (IPv6 family)
 ifa_prefixlen   = 0x00000040 (40) (first 64 bits, /64)
 ifa_flags       = 0x00000000 (00) (link flags)
 ifa_scope       = 0x00000000 (00) (link scope)
 ifa_index       = 0x00000000 (00.00.00.00) (link index)

 local_len       = 0x00000014 (14.00) local attribute length (0x14 = 0x2C - 0x18)
 local_type      = 0x00000002 (02.00) IFA_LOCAL (local address type)
 local           = 0x20010db8, 0x1a3457cf, 0x00000000, 0x00000000,
           (20.01.0d.b8.1a.34.57.cf.00.00.00.00.00.00.00.00)
           (local ipv6 address)

 address_len     = 0x00000014 (14.00) address attribute length (0x14 = 0x24
 address_type    = 0x00000014 (01.00) IFA_ADDRESS (address type)
 address         = 0x20010db8, 0x1a3457cf, 0x00000000, 0x00000000,
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

=item B<$address>

When $success is 1, the added address.

When $success is 0, a string containing a description of the error.

=item B<$device>

When $success is 1, the device (eth0, etc.) accepting the address.

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

=item IO::Interface::Simple

Used to get the device index, as required by the Netlink protocol.

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
