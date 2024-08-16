package Cpanel::DnsUtils::ReverseDns;

# cpanel - Cpanel/DnsUtils/ReverseDns.pm           Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

use Cpanel::DNS::Unbound::Async ();
use Promise::XS                 ();
use Cpanel::PromiseUtils        ();

use Try::Tiny;

our %_nameservers;

=encoding utf-8

=head1 NAME

Cpanel::DnsUtils::ReverseDns - Utility functions for dealing with rDNS

=head1 SYNOPSIS

    use Cpanel::DnsUtils::ReverseDns ();

    my ($is_valid, $ptr_record) = Cpanel::DnsUtils::ReverseDns::validate_ipv4_ptr_record("1.2.3.4");
    my ($is_valid, $ptr_record) = Cpanel::DnsUtils::ReverseDns::validate_ipv6_ptr_record("0:0:0:0:0:ffff:c0a8:7b2d");

    my ($is_valid, $ptr_record) = Cpanel::DnsUtils::ReverseDns::validate_ptr_record("1.2.3.4");
    my ($is_valid, $ptr_record) = Cpanel::DnsUtils::ReverseDns::validate_ptr_record("0:0:0:0:0:ffff:c0a8:7b2d");

    my $ip_to_ptr = Cpanel::DnsUtils::ReverseDns::validate_ptr_records_for_ips(["1.2.3.4", "0:0:0:0:0:ffff:c0a8:7b2d"]);

=head1 DESCRIPTION

This module provides utility methods to validate the PTR records for IPv4 and IPv6 addresses.

=head1 FUNCTIONS

=cut

=head2 validate_ptr_records_for_ips

Takes a list of IP addresses and validates the PTR records for them

=over 2

=item Input

=over 3

=item C<ARRAYREF>

An C<ARRAYREF> of IP addresses to validate

=back

=item Output

=over 3

=item C<HASHREF>

A C<HASHREF> where the key is the IP address and the value is a C<HASHREF> describing the PTR record.

See C<validate_ipv6_ptr_record> for details on the individual values.

=back

=back

=cut

sub validate_ptr_records_for_ips {

    my ($ips) = @_;

    my %ip_to_ptr = ();

    my %ip_ptr_p;

    foreach my $ip (@$ips) {

        $ip_ptr_p{$ip} ||= _validate_ptr_record_p($ip)->catch(
            sub ($why) {
                return {
                    ip_address => $ip,
                    state      => "ERROR",
                    error      => Cpanel::Exception::get_string($why),
                };
            }
        )->then(
            sub {
                $ip_to_ptr{$ip} = shift;
            }
        );
    }

    my $all_p = Promise::XS::all( values %ip_ptr_p )->then(
        sub {
            return \%ip_to_ptr;
        }
    );

    return Cpanel::PromiseUtils::wait_anyevent($all_p)->get();
}

=head2 promise($details_hr) = validate_ptr_record( $ADDR )

A thin wrapper for C<validate_ipv6_ptr_record> and C<validate_ipv4_ptr_record> that performs a simple inspection of the input and calls the appropriate validation method.

If the input contains a ‘.’ character, it's handed off to C<validate_ipv4_ptr_record>, if the input contains a ‘:’ it's handed off to C<validate_ipv6_ptr_record>.

Otherwise this method dies with an C<InvalidParameter> exception.

=over 2

=item Input

=over 3

=item C<SCALAR>

The IP address to validate

=back

=item Output

=over 3

=item C<SCALAR>

A boolean that is truthy if and only if the IP address has a
fully valid PTR record.

=item C<HASHREF>

A C<HASHREF> describing the PTR record.

The PTR record is as described in the C<validate_ipv6_ptr_record> output, with an added C<ip_version> key set to 4 or 6 describing the IP version.

=back

=back

=cut

sub _validate_ptr_record_p ($ip) {

    # Just check here for . vs : to determine which IP version we got back
    # The corresponding validate_ipv4/6_ptr_record methods will do a full validation of the input

    my $ip_version;

    if ( index( $ip, "." ) != -1 ) {
        $ip_version = 4;
    }
    elsif ( index( $ip, ":" ) != -1 ) {
        $ip_version = 6;
    }
    else {
        return _reject( Cpanel::Exception::create( 'InvalidParameter', "“[_1]” is not a valid IP address.", [$ip] ) );
    }

    my $validator_fn = "_validate_ipv${ip_version}_ptr_p";

    return __PACKAGE__->can($validator_fn)->($ip)->then(
        sub ($res_hr) {
            $res_hr->{'ip_version'} = $ip_version;

            return $res_hr;
        }
    );
}

=head2 promise($details_hr) = _validate_ipv6_ptr_p( $ipv6_addr )

Validates IPv6 PTR records by doing the lookup for the PTR records, then verifying that they resolve to hostnames that have an AAAA record that points back to the IPv6 address.

Note that if there are multiple PTR records, all of them must be valid for an IP to be considered valid.

See https://tools.ietf.org/html/draft-ietf-dnsop-reverse-mapping-considerations-06 for more details.

=over

=item Input

=over

=item C<SCALAR>

The IPv6 address to validate.

=back

=item Output

=over

=item C<HASHREF>

A C<HASHREF> containing details about the PTR records with the following keys:

=over

=item C<arpa_domain>

The domain that should have a PTR record. This domain is basically just the IP address backwards with .ip6.arpa.

=item C<ip_address>

The IP address being tested

=item C<nameservers>

An array of nameservers that control the IP address’s PTR record(s).

=item C<state>

A human and machine readable code indicating the state of the PTR records for the IP address, one of:

=over

=item C<VALID>

The PTR record is valid

=item C<MISSING_PTR>

There are no PTR records for the IP

=item C<IP_IS_PRIVATE>

The IP address is a private one (in which case it will never have a PTR record)

=item C<PTR_MISMATCH>

One or more of the PTR records points to a domain that does not point back to the IP address

=item C<ERROR>

A DNS lookup error occurred while attempting to validate the PTR

=back

=item C<error>

If the C<state> is C<ERROR> this indicates what the DNS error was.

=item C<ptr_records>

An C<ARRAYREF> of the PTR records found for the IP address, each entry in the C<ARRAYREF> is a C<HASHREF> containing the following keys:

=over

=item C<domain>

The domain that the PTR record points to

=item C<forward_records>

An C<ARRAYREF> of IP addresses that the domain resolves to (AAAA records for IPv6)

=item C<state>

A human and machine readable code indicating the state of the forward records for the IP address, one of:

=over

=item C<VALID>

The PTR points to a domain that has an AAAA record that points back to the IP address

=item C<MISSING_FWD>

The PTR points to a domain that has no AAAA records

=item C<FWD_MISMATCH>

The PTR points to a domain that does not have an A/AAAA record that points back to the IP address.

=item C<ERROR>

There was a DNS lookup error when querying the AAAA record for the domain the PTR points to.

=back

=item C<error>

If the C<state> is C<ERROR>, this indicates what the DNS error was.

=back

=back

=back

=back

=cut

sub _validate_ipv6_ptr_p ($ip) {

    if ( !length $ip ) {
        require Cpanel::Exception;
        return _reject( Cpanel::Exception::create( 'MissingParameter', "You must provide a valid [asis,IPv6] address to verify a [asis,PTR] record." ) );
    }

    require Cpanel::Validate::IP;
    if ( !Cpanel::Validate::IP::is_valid_ipv6($ip) ) {
        require Cpanel::Exception;
        return _reject( Cpanel::Exception::create( 'InvalidParameter', "You must provide a valid [asis,IPv6] address to verify a [asis,PTR] record." ) );
    }

    require Cpanel::IPv6::Normalize;
    ( undef, $ip ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($ip);

    my $in_addr_arpa = _qname_for_ip6($ip);

    my $expand_r = sub {
        my ($in) = @_;
        my ( undef, $expanded ) = Cpanel::IPv6::Normalize::normalize_ipv6_address($in);
        return $expanded;
    };
    return _validate_ptr_p( $ip, $in_addr_arpa, 'AAAA', $expand_r );
}

=head2 _validate_ipv4_ptr_p

Validates IPv4 PTR records by doing the lookup for the PTR records, then verifying that they resolve to hostnames that have an A record that points back to the IPv4 address.

Note that if there are multiple PTR records, all of them must be valid for an IP to be considered valid.

See https://tools.ietf.org/html/draft-ietf-dnsop-reverse-mapping-considerations-06 for more details.

=over 2

=item Input

=over 3

=item C<SCALAR>

The IPv4 address to validate.

=back

=item Output

=over 3

The output for this function is the same as the IPv6 version except related to IPv4 .in-addr.arpa records and their associated A records.

See the docs for C<_validate_ipv6_ptr_p> for details.

=back

=back

=cut

sub _validate_ipv4_ptr_p ($ip) {
    if ( !length $ip ) {
        require Cpanel::Exception;
        return _reject( Cpanel::Exception::create( 'MissingParameter', "You must provide a valid [asis,IPv4] address to verify a [asis,PTR] record." ) );
    }

    require Cpanel::Validate::IP::v4;
    if ( !Cpanel::Validate::IP::v4::is_valid_ipv4($ip) ) {
        require Cpanel::Exception;
        return _reject( Cpanel::Exception::create( 'InvalidParameter', "You must provide a valid [asis,IPv4] address to verify a [asis,PTR] record." ) );
    }

    my $in_addr_arpa = _qname_for_ip4($ip);

    return _validate_ptr_p( $ip, $in_addr_arpa, 'A', sub { $_[0] } );
}

sub _validate_ptr_p {

    my ( $ip, $in_addr_arpa, $forward_type, $expand_r ) = @_;

    my $ub = Cpanel::DNS::Unbound::Async->new();

    my @forward_lookups;
    my @arpa_nameservers;

    my %result = (
        ip_address  => $ip,
        arpa_domain => $in_addr_arpa,
        ptr_records => \@forward_lookups,
        nameservers => \@arpa_nameservers,
        error       => undef,
    );

    require Cpanel::IP::Utils;
    if ( Cpanel::IP::Utils::get_private_mask_bits_from_ip_address($ip) ) {
        $result{'state'} = 'IP_IS_PRIVATE';

        return Promise::XS::resolved( \%result );
    }

    my $ptr_promise = $ub->ask( $in_addr_arpa, 'PTR' )->then(
        sub ($result) {

            my @ptrs = @{ $result->decoded_data };

            my $d = Promise::XS::deferred();

            if (@ptrs) {

                my @promises;

                for my $name (@ptrs) {
                    my @fwd_recs;

                    my %fwd_lookup = (
                        error           => undef,
                        domain          => $name,
                        forward_records => \@fwd_recs
                    );

                    push @forward_lookups, \%fwd_lookup;

                    push @promises, $ub->ask( $name, $forward_type )->then(
                        sub ($result) {
                            @fwd_recs = @{ $result->decoded_data() };

                            if (@fwd_recs) {

                                # A PTR value is valid when at least one of its
                                # forward (A/AAAA) records equals $ip.
                                foreach my $a_rec (@fwd_recs) {
                                    if ( $expand_r->($a_rec) eq $ip ) {
                                        $fwd_lookup{'state'} = "VALID";
                                        last;
                                    }
                                }

                                $fwd_lookup{'state'} ||= 'FWD_MISMATCH';
                            }
                            else {
                                $fwd_lookup{'state'} = 'MISSING_FWD';
                            }

                            if ( $fwd_lookup{'state'} ne 'VALID' ) {
                                $result{'state'} = 'PTR_MISMATCH';
                            }
                        },

                        sub ($err) {

                            # This seems strange … should it not be ERROR?
                            $result{'state'} = 'PTR_MISMATCH';

                            @fwd_lookup{ 'state', 'error' } = (
                                'ERROR',
                                Cpanel::Exception::get_string($err),
                            );
                        },
                    );
                }

                Promise::XS::all(@promises)->then( sub { $d->resolve() } );
            }
            else {
                $result{'state'} = 'MISSING_PTR';
                $d->resolve();
            }

            return $d->promise();
        },

        sub ($err) {
            @result{ 'state', 'error' } = (
                'ERROR',
                Cpanel::Exception::get_string($err),
            );
        },
    );

    require Cpanel::Async::GetNameservers;
    $_nameservers{$in_addr_arpa} ||= Cpanel::Async::GetNameservers::for_domain( $ub, $in_addr_arpa );
    $_nameservers{$in_addr_arpa}->then(
        sub ($nss_ar) {
            @arpa_nameservers = @$nss_ar;
        }
    );

    my $all_p = Promise::XS::all(
        $ptr_promise,
        $_nameservers{$in_addr_arpa},
    );

    return $all_p->then(
        sub {
            $result{'state'} ||= 'VALID';
            return \%result;
        }
    );
}

#----------------------------------------------------------------------

=head2 promise(data) = promise_ptrs_for_ip( $UB_ASYNC, $IP_ADDR )

This function initiates an asynchronous DNS lookup for $IP_ADDR’s PTR
records. $IP_ADDR is the IP address (either IPv4 or IPv6) in ASCII format.

Returns a promise that resolves to a reference to an array of the
decoded PTR values. Rejections are as L<Cpanel::DNS::Unbound::Async>’s
C<ask()> method gives.

=cut

sub promise_ptrs_for_ip ( $ub_async, $ip ) {
    my $qname;

    if ( index( $ip, ':' ) > -1 ) {
        require Cpanel::IP::Expand;
        my $expanded_ip = Cpanel::IP::Expand::expand_ip( $ip, 6 );

        $qname = _qname_for_ip6($expanded_ip);
    }
    else {
        $qname = _qname_for_ip4($ip);
    }

    return $ub_async->ask( $qname, 'PTR' )->then(
        sub { shift()->decoded_data() },
    );
}

sub _qname_for_ip4 ($addr) {
    return join( '.', reverse( split( '\.', $addr ) ), 'in-addr.arpa' );
}

sub _qname_for_ip6 ($addr) {

    # NB: This logic assumes that $addr is fully-expanded.
    return join( '.', reverse( split( '', $addr =~ tr{:}{}dr ) ), 'ip6.arpa' );
}

sub _reject ($error) {
    require Promise::XS;
    return Promise::XS::rejected($error);
}

1;
