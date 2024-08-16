package Cpanel::SocketIP;

# cpanel - Cpanel/SocketIP.pm                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use Socket        ();
use Cpanel::Alarm ();

our $VERSION = '1.3';

sub _resolveIpAddress {
    my ( $host, %p_options ) = @_;

    # CPANEL-3774: Due to the change from 'inet_ntoa' to 'inet_ntop'
    # we need to explicitly catch cases where $host is not set
    return if !$host;

    my $timeout = defined $p_options{'timeout'} && length $p_options{'timeout'} ? $p_options{'timeout'} : undef;

    # ensure we can do the lookup #
    do { require Carp; Carp::croak("no ipv6 support on perl < 5.14: $]") }
      if $p_options{'ipv6'} && $] < 5.014;

    my @trueaddresses;
    my $alarm;
    my @type = $p_options{'any_proto'} ? () : $p_options{'ipv6'} ? Socket::AF_INET6() : Socket::AF_INET();

    eval {
        $alarm = Cpanel::Alarm->new( $timeout, sub { local $SIG{'__DIE__'}; die; } )
          if $timeout;    # this is not a fatal event so we shouldn't log the die.
        my %seen;
        my @addresses;
        if ( $] < 5.014 ) {
            @addresses = gethostbyname($host);
        }
        else {
            @addresses = Socket::getaddrinfo( $host, @type );
        }
        foreach my $r ( reverse @addresses ) {
            last if !$r;
            my $address;
            if ( ref($r) ne ref( {} ) ) {
                $address = Socket::inet_ntoa($r);
            }
            elsif ( $r->{'family'} == Socket::AF_INET6() ) {
                next if !$p_options{'ipv6'} && !$p_options{'any_proto'};
                $address = Socket::inet_ntop( $r->{'family'}, ( Socket::unpack_sockaddr_in6( $r->{'addr'} ) )[1] );
            }
            elsif ( $r->{'family'} == Socket::AF_INET ) {
                next if $p_options{'ipv6'} && !$p_options{'any_proto'};
                $address = Socket::inet_ntop( $r->{'family'}, ( Socket::unpack_sockaddr_in( $r->{'addr'} ) )[1] );
            }
            next if exists $seen{$address};
            push @trueaddresses, $address;
            $seen{$address} = 1;
        }
    };

    undef $alarm;

    if ( $#trueaddresses == -1 ) {
        return wantarray ? @trueaddresses : 0;
    }
    else {
        return wantarray ? @trueaddresses : $trueaddresses[0];
    }
}

1;
