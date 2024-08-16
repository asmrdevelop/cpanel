package Cpanel::DnsUtils::Authority::Async;

# cpanel - Cpanel/DnsUtils/Authority/Async.pm      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::Authority::Async

=head1 SYNOPSIS

    my $authority = Cpanel::DnsUtils::Authority::Async->new();

    my @domains = ('google.com', 'bobs-stuff.com');
    my $promises_ar = $authority->has_local_authority(\@domains);

    for my $i (0 .. $#domains) {
        $promises_ar->[$i]->then( sub ($result_hr) {
            # ...
        } );
    }

=head1 DESCRIPTION

This module provides an async lookup of whether the local server is
authoritative over a given domain.

=cut

# perl -MCpanel::DnsUtils::Authority::Async -MCpanel::PromiseUtils -MData::Dumper -Mstrict -w -e'print Dumper( Cpanel::PromiseUtils::wait_anyevent( Promise::XS::all( @{ Cpanel::DnsUtils::Authority::Async->new()->has_local_authority(["whatwhat.texas.com", "say.google.com", "heyhey.tld"]) } )->then( sub { [ map { $_->[0] } @_ ] } ) )->get() )'

#----------------------------------------------------------------------

use parent 'Cpanel::Destruct::DestroyDetector';

# Brought in for its lightweight DNS packet parsing.
use AnyEvent::DNS ();

use Promise::XS ();

use Cpanel::Async::AskDnsAdmin           ();
use Cpanel::DNS::Unbound::Async          ();
use Cpanel::DnsUtils::Authority::Backend ();
use Cpanel::Domain::Zone                 ();

use constant {
    _SOA_NAME   => 0,
    _SOA_SERIAL => 6,
};

#----------------------------------------------------------------------

=head1 METHODS

=head2 $obj = I<CLASS>->new()

Instantiates this class. This retains a DNS cache and a connection
to dnsadmin.

=cut

sub new ($class) {
    return bless {
        _unbound  => Cpanel::DNS::Unbound::Async->new(),
        _dnsadmin => Cpanel::Async::AskDnsAdmin->new(),
    }, $class;
}

=head2 $promises_ar = I<OBJ>->has_local_authority(\@DOMAINS)

Returns a reference to an array of promises, one for each @DOMAINS.
(@DOMAINS may include wildcards.)

Each returned promise resolves to a hashref of:

=over

=item * C<local_zone> - The domain’s local zone, if any. (undef otherwise)

=item * C<public_zone> - The domain’s zone in DNS, if any. (undef otherwise)

=item * C<local_authority> - One of:

=over

=item * 1 - The local DNS cluster is authoritative for the domain.

=item * 0 - The local DNS cluster is B<NOT> authoritative for the domain.

=item * undef - An error prevented discovery of one of the above states.

=back

=item * C<error> - Whatever error may have prevented discovery of the
domain’s status.

=back

No returned promise will ever reject.

Note that, unlike L<Cpanel::DnsUtils::Authority>, this interface does
B<NOT> look up domains’ public nameservers.

=cut

sub has_local_authority ( $self, $domains_ar ) {

    # Order of operations:
    #
    # Run dnsadmin fetch for all domains. Once we have that result
    # fetch each zone’s public SOA.

    my %local_zone;
    my %local_soa_serial;

    my $get_zones_finished;

    my $dnsadmin_p = $self->_get_soa_and_zones_for_domains($domains_ar)->then(
        sub ($ret_ar) {
            for my $result (@$ret_ar) {
                my $domain = $result->{'domain'};

                $local_zone{$domain}       = $result->{'zone'};
                $local_soa_serial{$domain} = $result->{'soa'} || q<>;
            }

            return;
        },
    );

    my $unbound = $self->{'_unbound'};

    my @domain_queries;

    my $failed_domain_queries = 0;

    my %soa_query;

    for my $domain (@$domains_ar) {
        my %result;

        my $query_domain = $domain =~ s<\A\*\.><>r;

        push @domain_queries, $dnsadmin_p->then(
            sub {
                if ( my $zone = $local_zone{$domain} ) {
                    my $q = $soa_query{$zone} ||= $unbound->ask( $zone, 'SOA' );

                    return $q->then(
                        sub ($ub_result) {
                            my ( $public_zone, $public_soa_serial ) = _get_public_zone_and_soa_serial_from_soa_result($ub_result);

                            $result{'public_zone'} = $public_zone;

                            # Normally if you query foo.example.com and
                            # example.com exists but foo.example.com doesn’t
                            # you’ll get NXDOMAIN with an SOA record in the
                            # response’s authority section.
                            #
                            # That doesn’t always happen, though; the DNS
                            # server can also just send an empty response.
                            # When that happens then obviously we don’t
                            # exercise local authority (because no one does).
                            #
                            my $has_local_authority = $public_soa_serial && ( $local_soa_serial{$domain} eq $public_soa_serial );

                            $result{'local_authority'} = $has_local_authority || 0;
                        }
                    );
                }
                else {

                    # If there’s no local zone then we always
                    # lack local authority.
                    $result{'local_authority'} = 0;
                }
            }
        )->catch(
            sub ($err) {
                $result{'error'} = $err;
            }
        )->then(
            sub {
                $result{'local_zone'} = $local_zone{$domain};
                $result{'public_zone'} ||= undef;
                $result{'error'}       ||= undef;
                $result{'local_authority'} //= undef;

                return \%result;
            }
        );
    }

    return \@domain_queries;
}

sub _get_public_zone_and_soa_serial_from_soa_result ($result) {
    my $parse_hr = AnyEvent::DNS::dns_unpack( $result->answer_packet() );

    # SOA queries against zone names will return the SOA record in the
    # response packet’s answer section. SOA queries against subdomains
    # will NORMALLY return NXDOMAIN but will have the zone’s SOA record
    # in the response packet’s authority section. (That doesn’t always
    # happen, though; sometimes the authority response is empty.)
    #
    # So we assemble a list of the records from both of those sections
    # and take the first one.
    #
    my @rrs = map {
        grep { $_->[1] eq 'soa' } @{ $parse_hr->{$_} };
    } qw( an ns );

    return @{ $rrs[0] }[ _SOA_NAME, _SOA_SERIAL ];
}

sub _get_soa_and_zones_for_domains ( $self, $domains_ar ) {
    return Cpanel::Domain::Zone->new()->async_get_zones_for_domains(
        $self->{'_dnsadmin'},
        $domains_ar,
    )->then(
        sub ($result_ar) {
            my ( $domain_to_zone_map_hr, $zones_hr ) = @$result_ar;

            return Cpanel::DnsUtils::Authority::Backend::post_get_soa_and_zones_for_domains( $domains_ar, $domain_to_zone_map_hr, $zones_hr );
        }
    );
}

1;
