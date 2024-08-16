package Cpanel::Mail::SPF::Resolver;

# cpanel - Cpanel/Mail/SPF/Resolver.pm             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Mail::SPF::Resolver

=head1 SYNOPSIS

    my $resolver = Cpanel::Mail::SPF::Resolver->new();

    $resolver->cp_add_to_txt_cache( 'example.com', 'v=spf1 ..' );

    # Payload will be as set above:
    my $packet1 = $resolver->send( 'example.com', 'TXT' );

    # Payload will be from DNS:
    my $packet2 = $resolver->send( 'example.com', 'A' ) or do {
        my $err = $resolver->errorstring();
    };

=head1 DESCRIPTION

This module mimics enough of L<Net::DNS::Resolver>’s interface to use
as L<Mail::SPF::Server>’s C<dns_resolver> parameter.

It allows L<Mail::SPF::Server> to use cPanel’s DNS resolution logic
as well as a writable results cache.

=cut

#----------------------------------------------------------------------

use Cpanel::DnsUtils::ResolverSingleton ();
use Cpanel::Exception                   ();

use Net::DNS::RR     ();
use Net::DNS::Packet ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new()

Returns an instance of this class.

=cut

sub new ($class) {

    my %self = (
        _dns => scalar( Cpanel::DnsUtils::ResolverSingleton::singleton() ),
    );

    return bless \%self, $class;
}

#----------------------------------------------------------------------

=head2 I<OBJ>->cp_add_to_txt_cache( $QNAME, $VALUE )

Replaces the object’s results cache for $QNAME/C<TXT> with $VALUE.

=cut

sub cp_add_to_txt_cache ( $self, $qname, $value ) {

    my $packet = _make_packet( $qname, 'TXT' );

    # We don’t know how the original SPF record was split,
    # but we know no single character string can exceed 255 bytes.
    my @cstrings = unpack '(a255)*', $value;

    $packet->push(
        answer => Net::DNS::RR->new(
            name    => $qname,
            type    => 'TXT',
            txtdata => \@cstrings,
        ),
    );

    $self->{'_packet_cache'}{$qname}{'TXT'} = $packet;

    return $self;
}

sub _make_packet ( $qname, $qtype ) {
    return Net::DNS::Packet->new( $qname, $qtype ) || die "Failed to create Net::DNS::Packet for domain “$qname” with type “$qtype”: $@";
}

#----------------------------------------------------------------------

=head2 I<OBJ>->send( $QNAME, $QTYPE )

Mimics L<Net::DNS::Resolver>’s method of the same name, incorporating
any previous results as well as any that have been set via
C<cp_add_to_txt_cache()>.

=cut

sub send ( $self, $qname, $qtype ) {
    my $dns = $self->{'_dns'};

    my $error;

    my $packet = $self->{'_packet_cache'}{$qname}{$qtype};

    if ( !$packet ) {
        my $qresult = $dns->recursive_queries( [ [ $qname => $qtype ] ] )->[0];

        if ( $error = $qresult->{'error'} ) {
            if ( $error->isa('Cpanel::Exception::Timeout') ) {
                $error = 'timeout';    ## Mail::SPF looks for this.
            }
            else {
                $error = Cpanel::Exception::get_string($error);
            }
        }
        else {
            $packet = _make_packet( $qname, $qtype );

            my $ub_result = $qresult->{'result'};

            for my $rdata ( @{ $ub_result->{'data'} } ) {
                $packet->push(
                    answer => Net::DNS::RR->new(
                        name  => $ub_result->{'qname'},
                        type  => $ub_result->{'qtype'},
                        class => $ub_result->{'qclass'},
                        ttl   => $ub_result->{'ttl'},
                        rdata => $rdata,
                    )
                );
            }

            $self->{'_packet_cache'}{$qname}{$qtype} = $packet;
        }
    }

    $self->{'_err'} = $error;

    return $packet;
}

=head2 I<OBJ>->errorstring()

Mimics L<Net::DNS::Resolver>’s method of the same name.

=cut

sub errorstring ($self) {
    return $self->{'_err'};
}

1;
