package Cpanel::NAT::Diagnose;

# cpanel - Cpanel/NAT/Diagnose.pm                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::NAT::Diagnose

=head1 SYNOPSIS

    my $problems_ar = find_loopback_nat_problems( port => 53, timeout => 5 );

=head1 DESCRIPTION

This module contains logic to investigate potential NAT misconfigurations
and incompatibilities.

=cut

#----------------------------------------------------------------------

use Try::Tiny;

use Socket ();

use Cpanel::Autodie         ();
use Cpanel::Exception       ();
use Cpanel::NAT::Object     ();
use Cpanel::Socket::Timeout ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $status_ar = find_loopback_nat_problems( %OPTS )

For each NAT pair (i.e., local and public addresses), this determines
whether loopback NAT works on a given TCP port for that pair.

%OPTS are:

=over

=item * C<port> - The port number.

=item * C<timeout> - The C<connect()> timeout, in seconds.
(Fractional seconds are accepted.)

=back

The return is a reference to an array of:

=over

=item * 0) local address

=item * 1) public address

=item * 2) One of:

=over

=item * undef, if loopback NAT on the given C<port> works for this address
pair

=item * empty string, if loopback NAT on the given C<port> timed out
(and is thus assumed to be broken)

=item * some other string, if such error prevented us from determining
whether loopback NAT on the given C<port> works for this address pair

=back

=back

=cut

sub find_loopback_nat_problems (%opts) {
    my $port    = $opts{'port'}    || die 'Need port!';
    my $timeout = $opts{'timeout'} || die 'Need timeout!';

    my @problems;

    for my $pair_ar ( @{ Cpanel::NAT::Object->new()->ordered_list() // [] } ) {
        my ( $local, $public ) = @$pair_ar;
        next if !$local || !$public;

        try {

            # If we bind to $port on $addr successfully, then there’s no
            # service that listens on $addr/$port, and we can ignore it.

            if ( _addr_is_bound_on_port( $local, $port ) ) {
                Cpanel::Autodie::socket( my $s, Socket::AF_INET(), Socket::SOCK_STREAM(), 0 );
                my $addr_bin = Socket::pack_sockaddr_in( $port, Socket::inet_aton($public) );

                my $wto = Cpanel::Socket::Timeout::create_write( $s, $timeout );

                try {
                    Cpanel::Autodie::connect( $s, $addr_bin );

                    # If we connect, then there’s no problem.
                    push @problems, [ $local, $public, undef ];
                }
                catch {
                    my $errname = $_->error_name();
                    if ( $errname eq 'EINPROGRESS' ) {

                        # A timeout means loopback NAT is broken “normally”.
                        push @problems, [ $local, $public, q<> ];
                    }
                    else {
                        local $@ = $_;
                        die;
                    }
                }
            }
        }
        catch {
            push @problems, [ $local, $public, Cpanel::Exception::get_string($_) ];
        }
    }
    return \@problems;
}

# stubbed in tests
sub _addr_is_bound_on_port ( $addr, $port ) {
    my $addr_bin = Socket::inet_aton($addr) or die "Bad IPv4: [$addr]";

    Cpanel::Autodie::socket( my $s, Socket::AF_INET(), Socket::SOCK_STREAM(), 0 );

    my $has_svc;

    local $!;
    bind( $s, Socket::pack_sockaddr_in( $port, $addr_bin ) ) or do {
        my $err = $!;

        if ( $!{'EADDRINUSE'} ) {
            $has_svc = 1;
        }
        else {
            die "bind($port, $addr): $!";
        }
    };

    return $has_svc || 0;
}

1;
