package Cpanel::Linux::Netlink;

# cpanel - Cpanel/Linux/Netlink.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

#----------------------------------------------------------------------
# This module more or less assumes that you are familiar with Netlink.
#
# ... which is a troubled proposition because the kernel maintainers’ own
# documentation of the protocol is full of inaccuracies.
#
# This module parses Netlink data as a stream of messages, each of which is:
#   header
#   body
#   (“payload” - subprotocol data)
#
# The header indicates how long the message is; the body is of a length that
# should match the PROTOCOL given to Perl’s socket() function. Anything left
# over is considered “payload” data for a subprotocol; as of this writing,
# we have implemented part of RtNetlink (in RtNetlink.pm).
#
# This module is quite incomplete as an implementation of the entire
# protocol; however, it serves cPanel’s limited needs without recourse
# to external libraries, XS, etc.
#----------------------------------------------------------------------

use strict;
use warnings;

use constant DEBUG => 0;

use Cpanel::Exception      ();
use Cpanel::Pack           ();
use Cpanel::Pack::Template ();

my $NETLINK_READ_SIZE = 262144;    # Maximum size of netlink message

# for smaller reads, to keep more in L1 cache.
use constant PAGE_SIZE => 0x400;
use constant READ_SIZE => 8 * PAGE_SIZE;

our $PF_NETLINK = 16;
our $AF_INET    = 2;
our $AF_INET6   = 10;

our $NLMSG_NOOP    = 0x1;
our $NLMSG_ERROR   = 0x2;
our $NLMSG_DONE    = 0x3;
our $NLMSG_OVERRUN = 0x4;

our $NETLINK_INET_DIAG_26_KERNEL = 0;

our $NETLINK_INET_DIAG = 4;
our $NLM_F_REQUEST     = 1;
our $NLM_F_MULTI       = 2;        # /* Multipart message, terminated by NLMSG_DONE */
our $NLM_F_ROOT        = 0x100;
our $NLM_F_MATCH       = 0x200;    # in queries, return all matches
our $NLM_F_EXCL        = 0x200;    # in commands, don't alter if it exists
our $NLM_F_CREATE      = 0x400;    # in commands, create if it does not exist

our $NLM_F_ACK          = 4;
our $SOCK_DGRAM         = 2;
our $TCPDIAG_GETSOCK    = 18;
our $INET_DIAG_NOCOOKIE = 0xFFFFFFFF;

use constant {
    PACK_TEMPLATE_U16 => Cpanel::Pack::Template::PACK_TEMPLATE_U16,
    U16_BYTES_LENGTH  => Cpanel::Pack::Template::U16_BYTES_LENGTH,
    PACK_TEMPLATE_U32 => Cpanel::Pack::Template::PACK_TEMPLATE_U32,
    U32_BYTES_LENGTH  => Cpanel::Pack::Template::U32_BYTES_LENGTH,
};

my $NLMSG_HEADER_PACK_OBJ;
my $NLMSG_HEADER_PACK_OBJ_SIZE;

our @NLMSG_HEADER_TEMPLATE;

BEGIN {
    # do not remove the '' which force the string to be uncowed or exim will break - /etc/exim.pl.local

    @NLMSG_HEADER_TEMPLATE = (

        'nlmsg_length' => PACK_TEMPLATE_U32(),    #__u32 nlmsg_len;    /* Length of message including header. */
        'nlmsg_type'   => PACK_TEMPLATE_U16(),    #__u16 nlmsg_type;   /* Type of message content. */
        'nlmsg_flags'  => PACK_TEMPLATE_U16(),    #__u16 nlmsg_flags;  /* Additional flags. */
        'nlmsg_seq'    => PACK_TEMPLATE_U32(),    #__u32 nlmsg_seq;    /* Sequence number. */
        'nlmsg_pid'    => PACK_TEMPLATE_U32(),    #__u32 nlmsg_pid;    /* Sender port ID. */

    );
}

#======================================================================
#----------------------------------------------------------------------
# netlink_transaction() is the “heart” of this module,
# an implementation of the Netlink client protocol itself.
#
# You almost CERTAINLY should create logic that wraps this so that everyone
# doesn’t need to learn Netlink in order to reap this module’s benefits.
#----------------------------------------------------------------------

#These are netlink_transaction()’s required parameters.
my @NETLINK_XACTION_REQUIRED = (
    'message',          #hashref, to be sent via “send_pack_obj”
    'send_pack_obj',    #Cpanel::Pack instance
    'recv_pack_obj',    #Cpanel::Pack instance
    'sock',             #Perl socket
);

#Optional parameters:
#   - header            arrayref of key/value pairs, each optional:
#       nlmsg_flags, always gets |=’d with $NLM_F_REQUEST
#       nlmsg_type
#       nlmsg_seq (is this really necessary??)
#
#   - parser            coderef, receives positional args:
#       - message index, 0-based
#       - hashref from unpack of “recv_pack_obj”
#
#   - payload_parser    coderef, receives positional args:
#       - message index, same as for “parser”
#       - hashref from unpack of “recv_pack_obj”, same as for “parser”
#       - payload, the raw binary data (e.g., for RTNetlink)
#
my %_u16_cache;
my %_u32_cache;

sub netlink_transaction {
    my (%OPTS) = @_;

    foreach (@NETLINK_XACTION_REQUIRED) {

        # No Cpanel::Exception here due to where this module
        # is used (think about where we would not document
        # as this statement vague on purpose).
        die "$_ is required for netlink_transaction" if !$OPTS{$_};
    }
    my ( $message_ref, $send_pack_obj, $recv_pack_obj, $sock, $parser, $payload_parser, $header_parms_ar ) = @OPTS{ @NETLINK_XACTION_REQUIRED, 'parser', 'payload_parser', 'header' };

    my $packed_nlmsg = _pack_nlmsg_with_header( $send_pack_obj, $message_ref, $header_parms_ar );

    if (DEBUG) {
        require Data::Dumper;
        print STDERR "[request]:" . Data::Dumper::Dumper($message_ref);
    }

    printf STDERR "Send %v02x\n", $packed_nlmsg if DEBUG;

    send( $sock, $packed_nlmsg, 0 ) or die "send: $!";

    my $message_hr;
    my $packed_response = '';

    my $header_pack_size = $NLMSG_HEADER_PACK_OBJ->sizeof();
    my $recv_pack_size   = $recv_pack_obj->sizeof();

    my $msgcount = 0;
    my ( $msg, $u32, $u16, $nlmsg_length, $nlmsg_type, $nlmsg_flags );
  READ_LOOP:
    while ( !_nlmsg_type_indicates_finished_reading($message_hr) ) {
        sysread( $sock, $packed_response, $NETLINK_READ_SIZE, length $packed_response ) or die "sysread: $!";

      PARSE_LOOP:
        while (1) {

            $msg          = substr( $packed_response, 0, $header_pack_size, q<> );
            $u32          = substr( $msg,             0, U32_BYTES_LENGTH,  '' );
            $nlmsg_length = $_u32_cache{$u32} //= unpack( PACK_TEMPLATE_U32, $u32 );
            $u16          = substr( $msg, 0, U16_BYTES_LENGTH, '' );
            $nlmsg_type   = $_u16_cache{$u16} //= unpack( PACK_TEMPLATE_U16, $u16 );
            $u16          = substr( $msg, 0, U16_BYTES_LENGTH );
            $nlmsg_flags  = $_u16_cache{$u16} //= unpack( PACK_TEMPLATE_U16, $u16 );

            last PARSE_LOOP if !$nlmsg_length || length $packed_response < $nlmsg_length - $NLMSG_HEADER_PACK_OBJ_SIZE;

            print STDERR "Received message, total size: [$nlmsg_length]\n" if DEBUG;

            if ( $nlmsg_type == $NLMSG_ERROR ) {
                require Data::Dumper;

                my ( $errno, $msg ) = unpack 'i a*', $packed_response;

                die Cpanel::Exception::create( 'Netlink', [ error => do { local $! = -$errno }, message => $msg ] );
            }

            # This is needed to parse multipart messages because
            # the last (NLMSG_DONE) message has a payload of just
            # 4 (NUL) bytes. It *might* be OK to check for that
            # prior to this loop, but at this time it’s unclear whether
            # NLMSG_DONE messages could also contain a payload.
            if ( $recv_pack_size <= length $packed_response ) {

                #Remove $recv_pack_size bytes from the start of $packed_response.
                my $main_msg = substr( $packed_response, 0, $recv_pack_size, '' );

                $message_hr = $recv_pack_obj->unpack_to_hashref($main_msg);

                if (DEBUG) {
                    require Data::Dumper;
                    printf STDERR "Received %v02x\n", $main_msg;
                    print STDERR "[response]:" . Data::Dumper::Dumper($message_hr);
                }

                # If there is data left over, these are subprotocol attributes.
                my $payload = substr(
                    $packed_response,
                    0,
                    $nlmsg_length - $NLMSG_HEADER_PACK_OBJ_SIZE - $recv_pack_size,
                    q<>,
                );

                if ( $payload_parser && length $payload ) {
                    printf STDERR "payload: Received [%v02x]\n", $payload if DEBUG;
                    $payload_parser->( $msgcount, $message_hr, $payload );
                }
            }

            last READ_LOOP if _nlmsg_type_flags_indicates_finished_reading( $nlmsg_type, $nlmsg_flags );

            $msgcount++;
        }

    }

    # Parse Netlink Messages
    $parser->( $msgcount, $message_hr ) if $parser && $nlmsg_type;

    return 1;
}

#======================================================================
# connection_lookup() does a NETLINK_INET_DIAG transaction.
# Returns a hashref that fits @INET_DIAG_MSG_TEMPLATE.
#======================================================================

our @INET_DIAG_SOCKID_TEMPLATE = (
    'idiag_sport'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE16,    #__be16  idiag_sport;
    'idiag_dport'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE16,    #__be16  idiag_dport;
    'idiag_src_0'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_src[0];
    'idiag_src_1'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_src[1];
    'idiag_src_2'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_src[2];
    'idiag_src_3'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_src[3];
    'idiag_dst_0'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_dst[0];
    'idiag_dst_1'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_dst[1];
    'idiag_dst_2'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_dst[2];
    'idiag_dst_3'    => Cpanel::Pack::Template::PACK_TEMPLATE_BE32,    #__be32  idiag_dst[3];
    'idiag_if'       => Cpanel::Pack::Template::PACK_TEMPLATE_U32,     #__u32  idiag_if;
    'idiag_cookie_0' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,     #__u32  idiag_cookie[0];
    'idiag_cookie_1' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,     #__u32  idiag_cookie[1];
);

my $INET_DIAG_MSG_PACK_OBJ;
our @INET_DIAG_MSG_TEMPLATE = (
    'idiag_family'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_family;           /* Family of addresses. */
    'idiag_state'   => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_state;
    'idiag_timer'   => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_timer;
    'idiag_retrans' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_retrans;
    @INET_DIAG_SOCKID_TEMPLATE,                                        # inet_diag_sockid
    'idiag_expires' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,      #__u32   idiag_expires;
    'idiag_rqueue'  => Cpanel::Pack::Template::PACK_TEMPLATE_U32,      #__u32   idiag_rqueue;
    'idiag_wqueue'  => Cpanel::Pack::Template::PACK_TEMPLATE_U32,      #__u32   idiag_wqueue;
    'idiag_uid'     => Cpanel::Pack::Template::PACK_TEMPLATE_U32,      #__u32   idiag_uid;
    'idiag_inode'   => Cpanel::Pack::Template::PACK_TEMPLATE_U32       #__u32   idiag_inode;
);

my $INET_DIAG_REQ_PACK_OBJ;
our @INET_DIAG_REQ_TEMPLATE = (
    'idiag_family'  => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_family;           /* Family of addresses. */
    'idiag_src_len' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_src_len;
    'idiag_dst_len' => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_dst_len;
    'idiag_ext'     => Cpanel::Pack::Template::PACK_TEMPLATE_U8,       # __u8    idiag_ext;              /* Query extended information */
    @INET_DIAG_SOCKID_TEMPLATE,                                        #inet_diag_sockid
    'idiag_states' => Cpanel::Pack::Template::PACK_TEMPLATE_U32,       #__u32   idiag_states;           /* States to dump */
    'idiag_dbs'    => Cpanel::Pack::Template::PACK_TEMPLATE_U32        #__u32   idiag_dbs;           /* Tables to dump (NI) */
);

sub connection_lookup {
    my ( $source_address, $source_port, $dest_address, $dest_port ) = @_;

    die "A source port is required."      if !defined $source_port;
    die "A destination port is required." if !defined $dest_port;

    my ( $idiag_dst_0, $idiag_dst_1, $idiag_dst_2, $idiag_dst_3 );
    my ( $idiag_src_0, $idiag_src_1, $idiag_src_2, $idiag_src_3 );
    my ($idiag_family);

    if ( $dest_address =~ tr/:// ) {
        require Cpanel::IP::Expand;    # hide from exim but not perlcc - not eval quoted

        ( $idiag_dst_0, $idiag_dst_1, $idiag_dst_2, $idiag_dst_3 ) = unpack( 'N4', pack( 'n8', split /:/, Cpanel::IP::Expand::expand_ip($dest_address) ) );
        ( $idiag_src_0, $idiag_src_1, $idiag_src_2, $idiag_src_3 ) = unpack( 'N4', pack( 'n8', split /:/, Cpanel::IP::Expand::expand_ip($source_address) ) );
        $idiag_family = $AF_INET6;
    }
    else {
        my $u32_dest_address   = unpack( 'N', pack( 'C4', split( /\D/, $dest_address,   4 ) ) );
        my $u32_source_address = unpack( 'N', pack( 'C4', split( /\D/, $source_address, 4 ) ) );
        $idiag_src_0  = $u32_source_address;
        $idiag_dst_0  = $u32_dest_address;
        $idiag_family = $AF_INET;
    }

    my $sock;
    socket( $sock, $PF_NETLINK, $SOCK_DGRAM, $NETLINK_INET_DIAG ) or die "socket: $!";

    $INET_DIAG_REQ_PACK_OBJ ||= Cpanel::Pack->new( \@INET_DIAG_REQ_TEMPLATE );
    $INET_DIAG_MSG_PACK_OBJ ||= Cpanel::Pack->new( \@INET_DIAG_MSG_TEMPLATE );

    my %RESPONSE;
    netlink_transaction(
        'message' => {
            'idiag_family'   => $idiag_family,
            'idiag_dst_0'    => $idiag_dst_0,
            'idiag_dst_1'    => $idiag_dst_1,
            'idiag_dst_2'    => $idiag_dst_2,
            'idiag_dst_3'    => $idiag_dst_3,
            'idiag_dport'    => $dest_port,
            'idiag_src_0'    => $idiag_src_0,
            'idiag_src_1'    => $idiag_src_1,
            'idiag_src_2'    => $idiag_src_2,
            'idiag_src_3'    => $idiag_src_3,
            'idiag_sport'    => $source_port,
            'idiag_cookie_0' => $INET_DIAG_NOCOOKIE,
            'idiag_cookie_1' => $INET_DIAG_NOCOOKIE,
        },
        'sock'          => $sock,
        'send_pack_obj' => $INET_DIAG_REQ_PACK_OBJ,
        'recv_pack_obj' => $INET_DIAG_MSG_PACK_OBJ,
        'parser'        => sub {
            my ( undef, $response_ref ) = @_;
            %RESPONSE = %$response_ref if ( $response_ref && 'HASH' eq ref $response_ref );
        }
    );

    return \%RESPONSE;
}

#======================================================================

my @NETLINK_SEND_HEADER = (
    'nlmsg_length' => undef,              #gets put in place
    'nlmsg_type'   => $TCPDIAG_GETSOCK,
    'nlmsg_flags'  => 0,                  #gets |=’d with $NLM_F_REQUEST
    'nlmsg_pid'    => undef,              #gets put in place
    'nlmsg_seq'    => 2,                  #default
);

sub _pack_nlmsg_with_header {
    my ( $send_pack_obj, $message_ref, $header_parms_ar ) = @_;

    my $nlmsg = $send_pack_obj->pack_from_hashref($message_ref);

    if ( !$NLMSG_HEADER_PACK_OBJ ) {
        $NLMSG_HEADER_PACK_OBJ      = Cpanel::Pack->new( \@NLMSG_HEADER_TEMPLATE );
        $NLMSG_HEADER_PACK_OBJ_SIZE = $NLMSG_HEADER_PACK_OBJ->sizeof();
    }

    my %header_data = (
        @NETLINK_SEND_HEADER,
        ( $header_parms_ar ? @$header_parms_ar : () ),
        nlmsg_length => $NLMSG_HEADER_PACK_OBJ_SIZE + length $nlmsg,
        nlmsg_pid    => $$,
    );

    $header_data{'nlmsg_flags'} |= $NLM_F_REQUEST;

    my $hdr_str = $NLMSG_HEADER_PACK_OBJ->pack_from_hashref( \%header_data );

    return $hdr_str . $nlmsg;
}

sub _nlmsg_type_indicates_finished_reading {
    return _nlmsg_type_flags_indicates_finished_reading( $_[0]->{'nlmsg_type'}, $_[0]->{'nlmsg_flags'} );
}

#my ( $nlmsg_type, $nlmsg_flags ) = @_;
sub _nlmsg_type_flags_indicates_finished_reading {
    return 0 if !length $_[0];

    #see https://www.infradead.org/~tgr/libnl/doc/core.html#core_multipart
    return ( $_[0] == $NLMSG_ERROR || ( $_[1] & $NLM_F_MULTI && $_[0] == $NLMSG_DONE ) || !( $_[1] & $NLM_F_MULTI ) ) ? 1 : 0;
}

sub expect_acknowledgment {
    my ( $my_sysread, $socket, $sequence ) = @_;

    my $NETLINK_HEADER = Cpanel::Pack->new( \@NLMSG_HEADER_TEMPLATE );

    my $response_buffer = '';
    my $header_hr;
    my $error_code;

    do {
        while ( length $response_buffer < $NETLINK_HEADER->sizeof() ) {
            $my_sysread->( $socket, \$response_buffer, READ_SIZE(), length $response_buffer ) or return "sysread, message header: $!";
        }
        $header_hr = $NETLINK_HEADER->unpack_to_hashref( substr( $response_buffer, 0, $NETLINK_HEADER->sizeof() ) );
        while ( length $response_buffer < $header_hr->{nlmsg_length} ) {
            $my_sysread->( $socket, \$response_buffer, READ_SIZE(), length $response_buffer ) or return "sysread, message body: $!";
        }

        # pulls one mesage off the repsonse buffer, note the 4th parameter which replaces the message in response_buffer with ''
        my $message = substr( $response_buffer, 0, $header_hr->{nlmsg_length}, '' );
        $error_code = 0;
        if ( $header_hr->{nlmsg_type} == $NLMSG_ERROR ) {
            $error_code = unpack( Cpanel::Pack::Template::PACK_TEMPLATE_U32, substr( $message, $NETLINK_HEADER->sizeof(), Cpanel::Pack::Template::U32_BYTES_LENGTH ) );
        }
        if ( $header_hr->{nlmsg_seq} eq $sequence ) {
            if ( $header_hr->{nlmsg_type} == $NLMSG_ERROR && $error_code != 0 ) {
                local $! = -$error_code;
                return "Received error code when expecting acknowledgement: $!\n";
            }
            if ( $header_hr->{nlmsg_type} == $NLMSG_OVERRUN ) {
                return "Data lost due to message overrun";
            }
            if ( $header_hr->{nlmsg_type} == $NLMSG_DONE ) {
                return "Received multipart data when expecting ACK";
            }
        }
    } while ( $header_hr->{nlmsg_seq} ne $sequence || $header_hr->{nlmsg_type} != $NLMSG_ERROR || $error_code != 0 );
    return undef;
}

1;
__END__

=pod

=head1 NAME

Cpanel::Linux::Netlink - Netlink utilities for Linux.

=head1 SYNOPSIS

    # Read responses till a request is acknowledged or in error
    my $error = Cpanel::Linux::Netlink::expect_acknowledgement( \&sysread, $socket, $sequence );

    if ( $error ) {
        die $error; # contains a message detaling the error.
    }

=head1 DESCRIPTION

Cpanel::Linux::Netlink provides routines useful for interacting with a Netlink Protocol Socket.

=head1 METHODS

=head2 B<$error> = Cpanel::Linux::Netlink::expect_acknowlegement( \&sysread, $socket, $sequence );

Read from a netlink socket until the stream acknowledges or terminates in error the conversation
related to the seqence id $sequence.  This routine will either exit when the acknowledgement is
returned, when an error is returned, or when a multipart-data stream is completed.

Timeouts have been deliberately not incorporated, because the response is directly written by
from the kernel, and a delay would indicate a locked kernel.  The protocol also guarantees a
response of some kind for each request, barring a kernel failure.

=over 4

=item B<\&sysread>

A reference to a variable containing the systread implementation.  This is structured as such
for ease of unit testing, so one can pass in custom sysreads that simulate socket communications
to permit testing of rare, or unlikely netlink communication patterns, including communication
failures.

=item B<$socket>

A reference to the socket the expected response should be read from.

=item B<$sequence>

The sequence id the request was tagged with.

=back

=head3 B<Returns>

=over 4

=item B<$error>

Undef, if the acknowlegement is read.

A scalar string containing the error message, if an error is encountered.

=back

=head1 DIAGNOSTICS

=over 4

=item B<sysread, message header: $!>

A netlink response could not be read because the netlink message header was incomplete.
A underlying system error was raised, with the text for the error included after the first colon.

=item B<sysread, message body: $!>

A netlink response could not be read because the netlink body was incomplete.
A underlying system error was raised, with the text for the error included after the first colon.

=item B<Received error code when expecting acknowledgement: $!>

A underlying system error was raised, with the text for the error included after the first colon.

=item B<Data lost due to message overrun>

The request was received, but the response data was sent fast enough and the kernel overwrote the response.

=item B<Received multipart data when expecting ACK>

The request was expecting an acknowledgement, but a list of reverse commands (netlink data) was received.

=back

=head1 CONFIGURATION AND ENVIRONMENT

This module requires a Linux operating system.

=head1 DEPENDENCIES

This module uses:

=over 8

=item Cpanel::Pack

=item Cpanel::Pack::Template

=back

=head1 INCOMPATIBILITIES

No known incompatibilities.

=head1 BUGS AND LIMITATIONS

Currently the filtering of response messages does not properly filter input by
port id.  Netlink may shift the port id between the first and second response
actions on a socket, and the architecture of our useage isn't poised to follow
that shift.  While this might sound bad, it is exactly the same design choice that
/sbin/ip uses internally.

This limitation means that a good $sequence number should be chosen for all Netlink
requests.  Until all requests are atomically managed, we recommend selecting a
pseudo-random $sequence number.
