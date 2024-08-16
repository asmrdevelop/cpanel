package Cpanel::Linux::NetlinkConstants;

# cpanel - Cpanel/Linux/NetlinkConstants.pm        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

our $VERSION = '1.00';

use Cpanel::Pack::Template ();

# Route information type flag, from <linux/if_addr.h>
use constant IFA_ADDRESS   => 1;
use constant IFA_LOCAL     => 2;
use constant IFA_LABEL     => 3;
use constant IFA_CACHEINFO => 6;

# Routing Table (Netlink) destination distance flags, from <linux/rtnetlink.h>
use constant RT_SCOPE_UNIVERSE => 0;
use constant RT_SCOPE_SITE     => 200;
use constant RT_SCOPE_LINK     => 253;
use constant RT_SCOPE_HOST     => 254;
use constant RT_SCOPE_NOWHERE  => 255;

# Routing Table (Netlink) request type, from <linux/rtnetlink.h>
use constant RTM_GETLINK  => 18;
use constant RTM_GETADDR  => 22;
use constant RTM_GETROUTE => 26;

# routing message attribute types, from <linux/rtnetlink.h>
use constant RTA_DST     => 1;
use constant RTA_PREFSRC => 7;

our @IFINFOMSG_TEMPLATE = (    #struct ifinfomsg
    'ifi_family' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  unsigned char ifi_family;
    '__ifi_pad'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  unsigned char __ifi_pad;
    'ifi_type'   => Cpanel::Pack::Template::PACK_TEMPLATE_U16,    #  unsigned short  ifi_type;   /* ARPHRD_* */
    'ifi_index'  => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    #  int   ifi_index;    /* Link index */
    'ifi_flags'  => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # unsigned  ifi_flags;    /* IFF_* flags  */
    'ifi_change' => Cpanel::Pack::Template::PACK_TEMPLATE_U32     # unsigned  ifi_change;   /* IFF_* change mask */
);

our @IFA_CACHEINFO_TEMPLATE = (                                   #struct ifa_cacheinfo
    'ifa_prefered' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # __u32 ifa_prefered;  # See: https://en,wiktionary,org/wiki/prefered   -- It is mispelled upstream
    'ifa_valid'    => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # __u32 ifa_valid;
    'cstamp'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,    # __u32 cstamp; /* created timestamp, hundredths of seconds */
    'tstamp'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32     # __u32 tstamp; /* updated timestamp, hundredths of seconds */
);

our @IFADDRMSG_TEMPLATE = (                                         # struct ifaddrmsg
    'ifa_family'    => Cpanel::Pack::Template::PACK_TEMPLATE_U8,    #  __u8    ifa_family;
    'ifa_prefixlen' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,    #  __u8    ifa_prefixlen;  /* The prefix length    */
    'ifa_flags'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,    #  __u8    ifa_flags;  /* Flags      */
    'ifa_scope'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,    #  __u8    ifa_scope;  /* Address scope    */
    'ifa_index'     => Cpanel::Pack::Template::PACK_TEMPLATE_U32    #  __u32   ifa_index;  /* Link index     */
);

our @RTMSG_TEMPLATE = (                                             # struct rtmsg
    'rtm_family'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      #  __u8    rtm_family;
    'rtm_dst_len' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      #  __u8    rtm_dst_len;
    'rtm_src_len' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      #  __u8    rtm_src_len;
    'rtm_tos'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,      #  __u8    rtm_tos;

    'rtm_table'    => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  __u8    rtm_table;  /* Routing table id */
    'rtm_protocol' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  __u8    rtm_protocol;  /* Routing protocol */
    'rtm_scope'    => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  __u8    rtm_scope;  /* Address scope    */
    'rtm_type'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,     #  __u8    rtm_type;

    'rtm_flags' => Cpanel::Pack::Template::PACK_TEMPLATE_U32        #  __u32   rtm_flags;  /* Flags     */
);

our @RTATTR_HEADER_TEMPLATE = (
    'rta_len'  => Cpanel::Pack::Template::PACK_TEMPLATE_U16,
    'rta_type' => Cpanel::Pack::Template::PACK_TEMPLATE_U16,
);
1;
__END__
=pod

=head1 Cpanel::Linux::NetlinkConstants

Cpanel::Linux::NetlinkConstants - constants relating to the netlink protocol.

=head1 VERSION

This documentation refers to Cpanel::Linux::NetlinkConstants version 1.00.

=head1 SYNOPSIS

    use Cpanel::Linux::NetlinkConstants ();

    if ($route_type == Cpanel::Linux::NetlinkContants::IFA_ADDRESS()) { ...  }
    if ($route_type == Cpanel::Linux::NetlinkContants::IFA_LOCAL()) { ...  }
    if ($route_type == Cpanel::Linux::NetlinkContants::IFA_LABEL()) { ...  }
    if ($route_type == Cpanel::Linux::NetlinkContants::IFA_CACHEINFO()) { ...  }

    if ($route_scope == Cpanel::Linux::NetlinkConstants::RT_SCOPE_UNIVERSE()) { ...}
    if ($route_scope == Cpanel::Linux::NetlinkConstants::RT_SCOPE_SITE()) { ... }
    if ($route_scope == Cpanel::Linux::NetlinkConstants::RT_SCOPE_LINK()) { ... }
    if ($route_scope == Cpanel::Linux::NetlinkConstants::RT_SCOPE_HOST()) { ... }
    if ($route_scope == Cpanel::Linux::NetlinkConstants::RT_SCOPE_NOWHERE()) { ... }

    if ($route_attribute == Cpanel::Linux::NetlinkConstants::RTA_DST()) { ... }
    if ($route_attribute == Cpanel::Linux::NetlinkConstants::RTA_PREFSRC()) { ... }

    my $request_type = Cpanel::Linux::NetlinkConstants::RTM_GETLINK();
    my $request_type = Cpanel::Linux::NetlinkConstants::RTM_GETADDR();
    my $request_type = Cpanel::Linux::NetlinkConstants::RTM_GETROUTE();

    my $send_address_object = Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFADDRMSG_TEMPLATE );
    my $send_interface_object = Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFINFOMSG_TEMPLATE );
    my $cachinfo_reply_object = Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::IFA_CACHEINFO_TEMPLATE );
    my $routing_table_object = Cpanel::Pack->new( \@Cpanel::Linux::NetlinkConstants::RTMSG_TEMPLATE );
    my $rt_attribute_object =  Cpanel::Pack->new( [ @Cpanel::Linux::NetlinkConstants::RTATTR_HEADER_TEMPLATE, 'rta_dst' => Cpanel::Pack::Template::PACK_TEMPLATE_U32 ] );

=head1 DESCRIPTION

Cpanel::Linux::NetlinkConstants provides a perl cache of the selected C constants defined in
<linux/rtnetlink.h>, <linux/netlink.h>, and <linux/if_addr.h> related to the sending of
netlink protocol requests in the support of cPanel operations.

The netlink protocol is a protocol that utilizes a socket handled directly by the kernel,
as such, it is the fastest means by which one can obtain the kernel's current routing table
information.

In addition to holding constants, this module also contains lists of packing definitions supporting
the marshalling and unmarshalling of data from a Perl representations to a binary representations
used in the protocol.

=head1 METHODS

This module contains no methods.

=head1 DIAGNOSTICS

This module raises no errors or warnings.

=head1 CONFIGURATION AND ENVIRONMENT

This module is insensitive to alternative configurations of the operating system.

=head1 DEPENDENCIES

This module uses Cpanel::Pack::Template to present pack / unpack information with
greater clarity.

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

While not dependent on the Linux operating system, this module contains constants
related to the internal workings of the netlink and rtnetlink protocols available
in a Linux operating system.  It is unlikely these constants will be of utility
outside of a Linux operating system.

Many of the netlink and rtnetlink constants are not included within this module,
please add required future constants to this module, but do so sparingly to reduce
the Resident Size Set of this module, which is used by memory-footprint sensitive
applications.

=head1 AUTHOR

Edwin Buck C<<< e.buck@cpanel.net >>>

=head1 LICENSE AND COPYRIGHT

Copyright 2022 cPanel, L.L.C.
This code is subject to the cPanel license.  Unauthorized copying is prohibited.
