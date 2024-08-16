package Cpanel::Socket::Micro;

# cpanel - Cpanel/Socket/Micro.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;

use Cpanel::Context             ();
use Cpanel::Socket::Constants   ();
use Cpanel::Socket::UNIX::Micro ();

#http://linux.die.net/man/7/ip
my $pack_template_AF_INET = q<
    s   #sin_family
    n   #sin_port - network order
    a4  #sin_addr
>;

#http://linux.die.net/man/7/ipv6
my $pack_template_AF_INET6 = q<
    s   #sin6_family
    n   #sin6_port - network order
    L   #sin6_flowinfo
    a16 #sin6_addr
    L   #sin6_scope_id
>;

#Well, not *ANY* type. For now this only does:
#   sockaddr_un
#   sockaddr_in
#   sockaddr_in6
#
#This takes, of course, the packed sockaddr_* data.
#
#It returns:
#   - the appropriate AF_* constant
#   - ...whatever Socket::unpack_sockaddr_* returns for the given type.
#
sub unpack_sockaddr_of_any_type {
    my ($packed) = @_;

    Cpanel::Context::must_be_list();

    my $type_constant = unpack( 's', $packed );

    my @socket_attrs;
    if ( $type_constant == $Cpanel::Socket::Constants::AF_UNIX ) {
        @socket_attrs = Cpanel::Socket::UNIX::Micro::unpack_sockaddr_un($packed);
    }
    elsif ( $type_constant == $Cpanel::Socket::Constants::AF_INET ) {
        @socket_attrs = unpack_sockaddr_in($packed);
    }
    elsif ( $type_constant == $Cpanel::Socket::Constants::AF_INET6 ) {
        @socket_attrs = unpack_sockaddr_in6($packed);
    }
    else {
        die "Unrecognized socket family: $type_constant";
    }

    return ( $type_constant, @socket_attrs );
}

sub unpack_sockaddr_in {
    my ($sockaddr) = @_;

    Cpanel::Context::must_be_list();

    return ( unpack $pack_template_AF_INET, $sockaddr )[ 1, 2 ];
}

#NOTE: This copies unpack_sockaddr_in6() from Socket.pm, not Socket6.pm.
#
sub unpack_sockaddr_in6 {
    my ($sockaddr) = @_;

    Cpanel::Context::must_be_list();

    return ( unpack $pack_template_AF_INET6, $sockaddr )[ 1, 3, 2, 4 ];
}

sub inet_ntoa {
    my ($binary) = @_;
    return join '.', unpack 'C4', $binary;
}

#equivalent to Socket::inet_ntop( AF_INET6, $binary ),
#...except that, while the above will convert to IPv4-within-IPv6 addresses,
#inet6_ntoa() will always give a fully colon-separated address.
#
#Note that this function's returned string is a COLLAPSED IPv6 address.
#
sub inet6_ntoa {
    my ($binary) = @_;

    my @doubles = unpack 'n8', $binary;

    #The tricky/interesting part: find the longest sequence of zeroes,
    #and reduce.

    my %zeroes;
    my @zero_sequences;

    for my $d ( 0 .. $#doubles ) {
        next if $doubles[$d] > 0;

        if ( defined $zeroes{ $d - 1 } ) {
            $zeroes{$d} = $zeroes{ $d - 1 };    #assign scalar ref
            ++$zeroes{$d}->{'length'};
        }
        else {
            $zeroes{$d} = { start => $d, length => 1 };
            push @zero_sequences, $zeroes{$d};
        }
    }

    if (@zero_sequences) {

        #We want the biggest; if there is a tie for biggest, use the earliest.
        my $biggest_seq = ( sort { $b->{'length'} <=> $a->{'length'} || $a->{'start'} <=> $b->{'start'} } @zero_sequences )[0];

        splice(
            @doubles,
            $biggest_seq->{'start'},
            $biggest_seq->{'length'},
            (q<>) x $biggest_seq->{'length'},
        );
    }

    my $str = join ':', map { length($_) ? sprintf( '%x', $_ ) : $_ } @doubles;

    $str =~ s<:::+><::>;

    return $str;
}

1;
