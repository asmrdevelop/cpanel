package Net::DNS::Nameserver;

use strict;
use warnings;

our $VERSION = (qw$Id: Nameserver.pm 1860 2021-12-11 09:19:50Z willem $)[2];


=head1 NAME

Net::DNS::Nameserver - DNS server class

=head1 SYNOPSIS

    use Net::DNS::Nameserver;

    my $nameserver = Net::DNS::Nameserver->new(
	LocalAddr	=> ['::1' , '127.0.0.1'],
	ZoneFile	=> "filename"
	);

    my $nameserver = Net::DNS::Nameserver->new(
	LocalAddr	=> '10.1.2.3',
	LocalPort	=> 5353,
	ReplyHandler	=> \&reply_handler
    );


=head1 DESCRIPTION

Net::DNS::Nameserver offers a simple mechanism for instantiation of
customised DNS server objects intended to provide test responses to
queries emanating from a client resolver.

It is not, nor will it ever be, a general-purpose DNS nameserver
implementation.

See L</EXAMPLE> for an example.

=cut

use IO::Socket::IP ();
use constant USE_SOCKET_IP => 1;

use integer;
use Carp;
use Net::DNS;
use Net::DNS::ZoneFile;

use IO::Socket;
use IO::Select;

use constant FORCE_IPv4 => 0;

use constant DEFAULT_ADDR => qw(::1 127.0.0.1);
use constant DEFAULT_PORT => 5353;

use constant STATE_ACCEPTED   => 1;
use constant STATE_GOT_LENGTH => 2;
use constant STATE_SENDING    => 3;

use constant PACKETSZ => 512;


#------------------------------------------------------------------------------
# Constructor.
#------------------------------------------------------------------------------

sub new {
	my ( $class, %self ) = @_;
	my $self = bless \%self, $class;
	if ( !exists $self{ReplyHandler} ) {
		if ( my $handler = UNIVERSAL::can( $class, "ReplyHandler" ) ) {
			$self{ReplyHandler} = sub { $handler->( $self, @_ ); };
		}
	}
	croak 'No reply handler!' unless ref( $self{ReplyHandler} ) eq "CODE";

	$self->ReadZoneFile( $self{ZoneFile} ) if exists $self{ZoneFile};

	# local server addresses must also be accepted by a resolver
	my $LocalAddr = $self{LocalAddr} || [DEFAULT_ADDR];
	my $resolver  = Net::DNS::Resolver->new( nameservers => $LocalAddr );
	$resolver->force_v4(1) unless USE_SOCKET_IP;
	$resolver->force_v4(1) if FORCE_IPv4;
	my @localaddresses = $resolver->nameservers;

	my $port = $self{LocalPort} || DEFAULT_PORT;
	$self{Truncate}	   = 1	 unless defined( $self{Truncate} );
	$self{IdleTimeout} = 120 unless defined( $self{IdleTimeout} );

	my @sock_tcp;						# All the TCP sockets we will listen to.
	my @sock_udp;						# All the UDP sockets we will listen to.

	# while we are here, print incomplete lines as they come along.
	local $| = 1 if $self{Verbose};

	foreach my $addr (@localaddresses) {

		#--------------------------------------------------------------------------
		# Create the TCP socket.
		#--------------------------------------------------------------------------

		print "\nCreating TCP socket $addr#$port - " if $self{Verbose};

		my $sock_tcp = inet_new(
			LocalAddr => $addr,
			LocalPort => $port,
			Listen	  => 64,
			Proto	  => "tcp",
			Reuse	  => 1,
			Blocking  => 0,
			);
		if ($sock_tcp) {
			push @sock_tcp, $sock_tcp;
			print "done.\n" if $self{Verbose};
		} else {
			carp "Couldn't create TCP socket: $!";
		}

		#--------------------------------------------------------------------------
		# Create the UDP Socket.
		#--------------------------------------------------------------------------

		print "Creating UDP socket $addr#$port - " if $self{Verbose};

		my $sock_udp = inet_new(
			LocalAddr => $addr,
			LocalPort => $port,
			Proto	  => "udp",
			);

		if ($sock_udp) {
			push @sock_udp, $sock_udp;
			print "done.\n" if $self{Verbose};
		} else {
			carp "Couldn't create UDP socket: $!";
		}

	}

	#--------------------------------------------------------------------------
	# Create the Select object.
	#--------------------------------------------------------------------------

	my $select = $self{select} = IO::Select->new;

	$select->add(@sock_tcp);
	$select->add(@sock_udp);

	return unless $select->count;

	#--------------------------------------------------------------------------
	# Return the object.
	#--------------------------------------------------------------------------

	return $self;
}


#------------------------------------------------------------------------------
# ReadZoneFile - Read zone file used by default reply handler
#------------------------------------------------------------------------------

sub ReadZoneFile {
	my ( $self, $file ) = @_;
	my $zonefile = Net::DNS::ZoneFile->new($file);

	my $RRhash = $self->{RRhash} = {};
	my $RRlist = [];
	while ( my $rr = $zonefile->read ) {
		my ($leaf) = $rr->{owner}->label;
		push @{$RRhash->{lc $leaf}}, $rr;

		# Warning: Nasty trick abusing SOA to reference zone RR list
		if ( $rr->type eq 'SOA' ) { $RRlist = $rr->{RRlist} = [] }
		else			  { push @$RRlist, $rr }
	}
	return;
}


#------------------------------------------------------------------------------
# ReplyHandler - Default reply handler serving RRs from zone file
#------------------------------------------------------------------------------

sub ReplyHandler {
	my ( $self, $qname, $qclass, $qtype, $peerhost, $query, $conn ) = @_;
	my $opcode = $query->header->opcode;
	my $rcode  = 'NOERROR';
	my @ans;

	my $lcase = lc $qname;					# assume $qclass always 'IN'
	my ( $leaf, @tail ) = split /\./, $lcase;
	my $RRhash = $self->{RRhash};
	my $RRlist = $RRhash->{$leaf} || [];			# hash, then linear search
	my @match  = grep { lc( $_->owner ) eq $lcase } @$RRlist;

	if ( $qtype eq 'AXFR' ) {
		my ($soa) = grep { $_->type eq 'SOA' } @match;
		if ($soa) { push @ans, $soa, @{$soa->{RRlist}}, $soa }
		else	  { $rcode = 'NOTAUTH' }

	} else {
		unless ( scalar(@match) ) {
			my $wildcard = join '.', '*', @tail;
			my $wildlist = $RRhash->{'*'} || [];
			foreach ( grep { lc( $_->owner ) eq $wildcard } @$wildlist ) {
				my $clone = bless {%$_}, ref($_);
				$clone->owner($qname);
				push @match, $clone;
			}
			$rcode = 'NXDOMAIN' unless @match;
		}
		@ans = grep { $_->type eq $qtype } @match;
	}

	return ( $rcode, \@ans, [], [], {aa => 1}, {} );
}


#------------------------------------------------------------------------------
# inet_new - Calls the constructor in the correct module for making sockets.
#------------------------------------------------------------------------------

sub inet_new {
	return USE_SOCKET_IP ? IO::Socket::IP->new(@_) : IO::Socket::INET->new(@_);
}

#------------------------------------------------------------------------------
# make_reply - Make a reply packet.
#------------------------------------------------------------------------------

sub make_reply {
	my ( $self, $query, $sock ) = @_;

	unless ($query) {
		print "ERROR: invalid packet\n" if $self->{Verbose};
		my $empty = Net::DNS::Packet->new();		# create empty reply packet
		my $reply = $empty->reply();
		$reply->header->rcode("FORMERR");
		return $reply;
	}

	if ( $query->header->qr() ) {
		print "ERROR: invalid packet (qr set), dropping\n" if $self->{Verbose};
		return;
	}

	my $reply  = $query->reply();
	my $header = $reply->header;
	my $headermask;
	my $optionmask;

	my $opcode  = $query->header->opcode;
	my $qdcount = $query->header->qdcount;

	unless ($qdcount) {
		$header->rcode("NOERROR");

	} elsif ( $qdcount > 1 ) {
		print "ERROR: qdcount $qdcount unsupported\n" if $self->{Verbose};
		$header->rcode("FORMERR");

	} else {
		my ($qr)   = $query->question;
		my $qname  = $qr->qname;
		my $qtype  = $qr->qtype;
		my $qclass = $qr->qclass;

		my $id = $query->header->id;
		print "query $id : $qname $qclass $qtype\n" if $self->{Verbose};

		my $peer = $sock->peerhost;
		my $conn = {
			peerhost => $peer,
			peerport => $sock->peerport,
			protocol => $sock->protocol,
			sockhost => $sock->sockhost,
			sockport => $sock->sockport
			};

		my ( $rcode, $ans, $auth, $add );
		my @arglist = ( $qname, $qclass, $qtype, $peer, $query, $conn );

		if ( $opcode eq "QUERY" ) {
			( $rcode, $ans, $auth, $add, $headermask, $optionmask ) =
					&{$self->{ReplyHandler}}(@arglist);

		} elsif ( $opcode eq "NOTIFY" ) {		#RFC1996
			if ( ref $self->{NotifyHandler} eq "CODE" ) {
				( $rcode, $ans, $auth, $add, $headermask, $optionmask ) =
						&{$self->{NotifyHandler}}(@arglist);
			} else {
				$rcode = "NOTIMP";
			}

		} elsif ( $opcode eq "UPDATE" ) {		#RFC2136
			if ( ref $self->{UpdateHandler} eq "CODE" ) {
				( $rcode, $ans, $auth, $add, $headermask, $optionmask ) =
						&{$self->{UpdateHandler}}(@arglist);
			} else {
				$rcode = "NOTIMP";
			}

		} else {
			print "ERROR: opcode $opcode unsupported\n" if $self->{Verbose};
			$rcode = "FORMERR";
		}

		if ( !defined($rcode) ) {
			print "remaining silent\n" if $self->{Verbose};
			return;
		}

		$header->rcode($rcode);

		$reply->{answer}     = [@$ans]	if $ans;
		$reply->{authority}  = [@$auth] if $auth;
		$reply->{additional} = [@$add]	if $add;
	}

	while ( my ( $key, $value ) = each %{$headermask || {}} ) {
		$header->$key($value);
	}

	while ( my ( $option, $value ) = each %{$optionmask || {}} ) {
		$reply->edns->option( $option, $value );
	}

	$header->print if $self->{Verbose} && ( $headermask || $optionmask );

	return $reply;
}


#------------------------------------------------------------------------------
# readfromtcp - read from a TCP client
#------------------------------------------------------------------------------

sub readfromtcp {
	my ( $self, $sock ) = @_;
	return -1 unless defined $self->{_tcp}{$sock};
	my $peer = $self->{_tcp}{$sock}{peer};
	my $buf;
	my $charsread = $sock->sysread( $buf, 16384 );
	$self->{_tcp}{$sock}{inbuffer} .= $buf;
	$self->{_tcp}{$sock}{timeout} = time() + $self->{IdleTimeout};	  # Reset idle timer
	print "Received $charsread octets from $peer\n" if $self->{Verbose};

	if ( $charsread == 0 ) {				# 0 octets means socket has closed
		print "Connection to $peer closed or lost.\n" if $self->{Verbose};
		$self->{select}->remove($sock);
		$sock->close();
		delete $self->{_tcp}{$sock};
		return $charsread;
	}
	return $charsread;
}

#------------------------------------------------------------------------------
# tcp_connection - Handle a TCP connection.
#------------------------------------------------------------------------------

sub tcp_connection {
	my ( $self, $sock ) = @_;

	if ( not $self->{_tcp}{$sock} ) {

		# We go here if we are called with a listener socket.
		my $client = $sock->accept;
		if ( not defined $client ) {
			print "TCP connection closed by peer before we could accept it.\n" if $self->{Verbose};
			return 0;
		}
		my $peerport = $client->peerport;
		my $peerhost = $client->peerhost;

		print "TCP connection from $peerhost:$peerport\n" if $self->{Verbose};
		$client->blocking(0);
		$self->{_tcp}{$client}{peer}	= "tcp:" . $peerhost . ":" . $peerport;
		$self->{_tcp}{$client}{state}	= STATE_ACCEPTED;
		$self->{_tcp}{$client}{socket}	= $client;
		$self->{_tcp}{$client}{timeout} = time() + $self->{IdleTimeout};
		$self->{select}->add($client);

		# After we accepted we will look at the socket again
		# to see if there is any data there. ---Olaf
		$self->loop_once(0);
	} else {

		# We go here if we are called with a client socket
		my $peer = $self->{_tcp}{$sock}{peer};

		if ( $self->{_tcp}{$sock}{state} == STATE_ACCEPTED ) {
			if ( not $self->{_tcp}{$sock}{inbuffer} =~ s/^(..)//s ) {
				return;				# Still not 2 octets ready
			}
			my $msglen = unpack( "n", $1 );
			print "$peer said his query contains $msglen octets\n" if $self->{Verbose};
			$self->{_tcp}{$sock}{state}	  = STATE_GOT_LENGTH;
			$self->{_tcp}{$sock}{querylength} = $msglen;
		}

		# Not elsif, because we might already have all the data
		if ( $self->{_tcp}{$sock}{state} == STATE_GOT_LENGTH ) {

			# return if not all data has been received yet.
			return if $self->{_tcp}{$sock}{querylength} > length $self->{_tcp}{$sock}{inbuffer};

			my $qbuf = substr( $self->{_tcp}{$sock}{inbuffer}, 0, $self->{_tcp}{$sock}{querylength} );
			substr( $self->{_tcp}{$sock}{inbuffer}, 0, $self->{_tcp}{$sock}{querylength} ) = "";
			my $query = Net::DNS::Packet->new( \$qbuf );
			if ( my $err = $@ ) {
				print "Error decoding query packet: $err\n" if $self->{Verbose};
				undef $query;			# force FORMERR reply
			}

			my $reply = $self->make_reply( $query, $sock );
			if ( not defined $reply ) {
				print "I couldn't create a reply for $peer. Closing socket.\n"
						if $self->{Verbose};
				$self->{select}->remove($sock);
				$sock->close();
				delete $self->{_tcp}{$sock};
				return;
			}
			my $reply_data = $reply->data(65535);	# limit to one TCP envelope
			warn "multi-packet TCP response not implemented" if $reply->header->tc;
			my $len = length $reply_data;
			$self->{_tcp}{$sock}{outbuffer} = pack( 'n a*', $len, $reply_data );
			print "Queued TCP response (2 + $len octets) to $peer\n"
					if $self->{Verbose};

			# We are done.
			$self->{_tcp}{$sock}{state} = STATE_SENDING;
		}
	}
	return;
}

#------------------------------------------------------------------------------
# udp_connection - Handle a UDP connection.
#------------------------------------------------------------------------------

sub udp_connection {
	my ( $self, $sock ) = @_;

	my $buf = "";

	$sock->recv( $buf, PACKETSZ );
	my ( $peerhost, $peerport, $sockhost ) = ( $sock->peerhost, $sock->peerport, $sock->sockhost );
	unless ( defined $peerhost && defined $peerport ) {
		print "the Peer host and sock host appear to be undefined: bailing out of handling the UDP connection"
				if $self->{Verbose};
		return;
	}

	print "UDP connection from $peerhost:$peerport to $sockhost\n" if $self->{Verbose};

	my $query = Net::DNS::Packet->new( \$buf );
	if ( my $err = $@ ) {
		print "Error decoding query packet: $err\n" if $self->{Verbose};
		undef $query;					# force FORMERR reply
	}

	my $reply = $self->make_reply( $query, $sock ) || return;

	my $max_len = ( $query && $self->{Truncate} ) ? $query->edns->size : undef;
	if ( $self->{Verbose} ) {
		local $| = 1;
		print "Maximum UDP size advertised by $peerhost#$peerport: $max_len\n" if $max_len;
		print "Writing response - ";
		print $sock->send( $reply->data($max_len) ) ? "done" : "failed: $!", "\n";

	} else {
		$sock->send( $reply->data($max_len) );
	}
	return;
}


sub get_open_tcp {
	my $self = shift;
	return keys %{$self->{_tcp}};
}


#------------------------------------------------------------------------------
# loop_once - Just check "once" on sockets already set up
#------------------------------------------------------------------------------

# This function might not actually return immediately. If an AXFR request is
# coming in which will generate a huge reply, we will not relinquish control
# until our outbuffers are empty.

#
#  NB  this method may be subject to change and is therefore left 'undocumented'
#

sub loop_once {
	my ( $self, $timeout ) = @_;

	print ";loop_once called with timeout: " . ( defined($timeout) ? $timeout : "undefined" ) . "\n"
			if $self->{Verbose} && $self->{Verbose} > 4;
	foreach my $sock ( keys %{$self->{_tcp}} ) {

		# There is TCP traffic to handle
		$timeout = 0.1 if $self->{_tcp}{$sock}{outbuffer};
	}
	my @ready = $self->{select}->can_read($timeout);

	foreach my $sock (@ready) {
		my $protonum = $sock->protocol;

		# This is a weird and nasty hack. Although not incorrect,
		# I just don't know why ->protocol won't tell me the protocol
		# on a connected socket. --robert
		$protonum = getprotobyname('tcp') if not defined $protonum and $self->{_tcp}{$sock};

		my $proto = getprotobynumber($protonum);
		if ( !$proto ) {
			print "ERROR: connection with unknown protocol\n"
					if $self->{Verbose};
		} elsif ( lc($proto) eq "tcp" ) {

			$self->readfromtcp($sock)
					&& $self->tcp_connection($sock);
		} elsif ( lc($proto) eq "udp" ) {
			$self->udp_connection($sock);
		} else {
			print "ERROR: connection with unsupported protocol $proto\n"
					if $self->{Verbose};
		}
	}
	my $now = time();

	# Lets check if any of our TCP clients has pending actions.
	# (outbuffer, timeout)
	foreach my $s ( keys %{$self->{_tcp}} ) {
		my $sock = $self->{_tcp}{$s}{socket};
		if ( $self->{_tcp}{$s}{outbuffer} ) {

			# If we have buffered output, then send as much as the OS will accept
			# and wait with the rest
			my $len	 = length $self->{_tcp}{$s}{outbuffer};
			my $sent = $sock->syswrite( $self->{_tcp}{$s}{outbuffer} ) || 0;
			print "Sent $sent of $len octets to ", $self->{_tcp}{$s}{peer}, ".\n"
					if $self->{Verbose};
			substr( $self->{_tcp}{$s}{outbuffer}, 0, $sent ) = "";
			if ( length $self->{_tcp}{$s}{outbuffer} == 0 ) {
				delete $self->{_tcp}{$s}{outbuffer};
				$self->{_tcp}{$s}{state} = STATE_ACCEPTED;
				if ( length $self->{_tcp}{$s}{inbuffer} >= 2 ) {

					# See if the client has send us enough data to process the
					# next query.
					# We do this here, because we only want to process (and buffer!!)
					# a single query at a time, per client. If we allowed a STATE_SENDING
					# client to have new requests processed. We could be easilier
					# victims of DoS (client sending lots of queries and never reading
					# from it's socket).
					# Note that this does not disable serialisation on part of the
					# client. The split second it should take for us to lookup the
					# next query, is likely faster than the time it takes to
					# send the response... well, unless it's a lot of tiny queries,
					# in which case we will be generating an entire TCP packet per
					# reply. --robert
					$self->tcp_connection( $self->{_tcp}{$s}{socket} );
				}
			}
			$self->{_tcp}{$s}{timeout} = time() + $self->{IdleTimeout};
		} else {

			# Get rid of idle clients.
			my $timeout = $self->{_tcp}{$s}{timeout};
			if ( $timeout - $now < 0 ) {
				print $self->{_tcp}{$s}{peer}, " has been idle for too long and will be disconnected.\n"
						if $self->{Verbose};
				$self->{select}->remove($sock);
				$sock->close();
				delete $self->{_tcp}{$s};
			}
		}
	}
	return;
}

#------------------------------------------------------------------------------
# main_loop - Main nameserver loop.
#------------------------------------------------------------------------------

sub main_loop {
	my $self = shift;

	while (1) {
		print "Waiting for connections...\n" if $self->{Verbose};

		# You really need an argument otherwise you'll be burning CPU.
		$self->loop_once(10);
	}
	return;
}


1;
__END__


=head1 METHODS

=head2 new

    $nameserver = Net::DNS::Nameserver->new(
	LocalAddr	=> ['::1' , '127.0.0.1'],
	ZoneFile	=> "filename"
	);

    $nameserver = Net::DNS::Nameserver->new(
	LocalAddr	=> '10.1.2.3',
	LocalPort	=> 5353,
	ReplyHandler	=> \&reply_handler,
	Verbose		=> 1,
	Truncate	=> 0
    );

Returns a Net::DNS::Nameserver object, or undef if the object
could not be created.

Each instance is configured using the following optional arguments:

    LocalAddr		IP address on which to listen	Defaults to loopback address
    LocalPort		Port on which to listen		Defaults to 5353
    ZoneFile		Name of file containing RRs
			accessed using the default
			reply-handling subroutine
    ReplyHandler	Reference to customised
			reply-handling subroutine
    NotifyHandler	Reference to reply-handling
			subroutine for queries with
			opcode NOTIFY (RFC1996)
    UpdateHandler	Reference to reply-handling
			subroutine for queries with
			opcode UPDATE (RFC2136)
    Verbose		Report internal activity	Defaults to 0 (off)
    Truncate		Truncates UDP packets that
			are too big for the reply	Defaults to 1 (on)
    IdleTimeout		TCP clients are disconnected
			if they are idle longer than
			this duration			Defaults to 120 (secs)

The LocalAddr attribute may alternatively be specified as a list of IP
addresses to listen to.
If the IO::Socket::IP library package is available on the system
this may also include IPv6 addresses.


The ReplyHandler subroutine is passed the query name, query class,
query type, peerhost, query record, and connection descriptor.
It must either return the response code and references to the answer,
authority, and additional sections of the response, or undef to leave
the query unanswered.  Common response codes are:

    NOERROR	No error
    FORMERR	Format error
    SERVFAIL	Server failure
    NXDOMAIN	Non-existent domain (name doesn't exist)
    NOTIMP	Not implemented
    REFUSED	Query refused

For advanced usage it may also contain a headermask containing an
hashref with the settings for the C<aa>, C<ra>, and C<ad>
header bits. The argument is of the form
C<< { ad => 1, aa => 0, ra => 1 } >>.

EDNS options may be specified in a similar manner using optionmask
C<< { $optioncode => $value, $optionname => $value } >>.


See RFC 1035 and the IANA dns-parameters file for more information:

  ftp://ftp.rfc-editor.org/in-notes/rfc1035.txt
  http://www.isi.edu/in-notes/iana/assignments/dns-parameters

The nameserver will listen for both UDP and TCP connections.
On Unix-like systems, unprivileged users are denied access to ports below 1024.

UDP reply truncation functionality was introduced in VERSION 830.
The size limit is determined by the EDNS0 size advertised in the query,
otherwise 512 is used.
If you want to do packet truncation yourself you should set C<Truncate>
to 0 and truncate the reply packet in the code of the ReplyHandler.

See L</EXAMPLE> for an example.

=head2 main_loop

    $ns->main_loop;

Start accepting queries. Calling main_loop never returns.


=head2 loop_once

    $ns->loop_once( [TIMEOUT_IN_SECONDS] );

Start accepting queries, but returns. If called without a parameter, the
call will not return until a request has been received (and replied to).
Otherwise, the parameter specifies the maximum time to wait for a request.
A zero timeout forces an immediate return if there is nothing to do.

Handling a request and replying obviously depends on the speed of
ReplyHandler. Assuming a fast ReplyHandler, loop_once should spend just a
fraction of a second, if called with a timeout value of 0.0 seconds. One
exception is when an AXFR has requested a huge amount of data that the OS
is not ready to receive in full. In that case, it will remain in a loop
(while servicing new requests) until the reply has been sent.

In case loop_once accepted a TCP connection it will immediately check if
there is data to be read from the socket. If not it will return and you
will have to call loop_once() again to check if there is any data waiting
on the socket to be processed. In most cases you will have to count on
calling "loop_once" twice.

A code fragment like:

    $ns->loop_once(10);
    while( $ns->get_open_tcp() ){
	$ns->loop_once(0);
    }

Would wait for 10 seconds for the initial connection and would then
process all TCP sockets until none is left.


=head2 get_open_tcp

In scalar context returns the number of TCP connections for which state
is maintained. In array context it returns IO::Socket objects, these could
be useful for troubleshooting but be careful using them.


=head1 EXAMPLE

The following example will listen on port 5353 and respond to all queries
for A records with the IP address 10.1.2.3.	 All other queries will be
answered with NXDOMAIN.	 Authority and additional sections are left empty.
The $peerhost variable catches the IP address of the peer host, so that
additional filtering on its basis may be applied.

    #!/usr/bin/perl

    use strict;
    use warnings;
    use Net::DNS::Nameserver;

    sub reply_handler {
	my ( $qname, $qclass, $qtype, $peerhost, $query, $conn ) = @_;
	my ( $rcode, @ans, @auth, @add );

	print "Received query from $peerhost to " . $conn->{sockhost} . "\n";
	$query->print;

	if ( $qtype eq "A" && $qname eq "foo.example.com" ) {
		my ( $ttl, $rdata ) = ( 3600, "10.1.2.3" );
		my $rr = Net::DNS::RR->new("$qname $ttl $qclass $qtype $rdata");
		push @ans, $rr;
		$rcode = "NOERROR";
	} elsif ( $qname eq "foo.example.com" ) {
		$rcode = "NOERROR";

	} else {
		$rcode = "NXDOMAIN";
	}

	# mark the answer as authoritative (by setting the 'aa' flag)
	my $headermask = {aa => 1};

	# specify EDNS options	{ option => value }
	my $optionmask = {};

	return ( $rcode, \@ans, \@auth, \@add, $headermask, $optionmask );
    }


    my $ns = Net::DNS::Nameserver->new(
	LocalPort    => 5353,
	ReplyHandler => \&reply_handler,
	Verbose	     => 1
	) || die "couldn't create nameserver object\n";


    $ns->main_loop;


=head1 BUGS

Limitations in perl make it impossible to guarantee that replies to
UDP queries from Net::DNS::Nameserver are sent from the IP-address
to which the query was directed.  This is a problem for machines with
multiple IP-addresses and causes violation of RFC2181 section 4.
Thus a UDP socket created listening to INADDR_ANY (all available
IP-addresses) will reply not necessarily with the source address being
the one to which the request was sent, but rather with the address that
the operating system chooses. This is also often called "the closest
address". This should really only be a problem on a server which has
more than one IP-address (besides localhost - any experience with IPv6
complications here, would be nice). If this is a problem for you, a
work-around would be to not listen to INADDR_ANY but to specify each
address that you want this module to listen on. A separate set of
sockets will then be created for each IP-address.


=head1 COPYRIGHT

Copyright (c)2000 Michael Fuhr.

Portions Copyright (c)2002-2004 Chris Reinhardt.

Portions Copyright (c)2005 Robert Martin-Legene.

Portions Copyright (c)2005-2009 O.M, Kolkman, RIPE NCC.

Portions Copyright (c)2017 Dick Franks.

All rights reserved.


=head1 LICENSE

Permission to use, copy, modify, and distribute this software and its
documentation for any purpose and without fee is hereby granted, provided
that the original copyright notices appear in all copies and that both
copyright notice and this permission notice appear in supporting
documentation, and that the name of the author not be used in advertising
or publicity pertaining to distribution of the software without specific
prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.


=head1 SEE ALSO

L<perl>, L<Net::DNS>, L<Net::DNS::Resolver>, L<Net::DNS::Packet>,
L<Net::DNS::Update>, L<Net::DNS::Header>, L<Net::DNS::Question>,
L<Net::DNS::RR>, RFC 1035

=cut

