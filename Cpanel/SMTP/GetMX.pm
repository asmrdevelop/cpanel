package Cpanel::SMTP::GetMX;

# cpanel - Cpanel/SMTP/GetMX.pm                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::SMTP::GetMX

=head1 DESCRIPTION

This module compiles MX data on locally-hosted user domains.

=cut

#----------------------------------------------------------------------

use Promise::ES6 ();

use constant _TIMEOUT => 30;

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $promise = assemble_mx_table( $UNBOUND_ASYNC )

This function finds MX data for all user-owned domains on the server.

The input is a L<Cpanel::DNS::Unbound::Async> instance.

The return is a hash reference whose keys are the user-controlled domains.
Each value is a promise object that resolves when that domain’s
last DNS query ends. The resolution is one of:

=over

=item * undef, if the MX query failed (A warning is generated if this
happens.)

=item * a reference to an array, each of whose values is a hash reference
like:

=over

=item * C<exchange> - The exchange name, from the MX record.

=item * C<preference> - The exchange’s preference, from the MX record.

=item * C<ipv4> - A reference to an array of the C<exchange>’s
IPv4 addresses. (Absent if C<exchange> is empty or if we fail to obtain
the list of addresses.)

=item * C<ipv6> - Like C<ipv4> but for IPv6 addresses.

=back

=back

The returned promises will always resolve, never reject.

=cut

use constant _RET_HASH_XFORM => {
    A    => 'ipv4',
    AAAA => 'ipv6',
};

# perl -MAnyEvent -MData::Dumper -MCpanel::SMTP::GetMX -MCpanel::DNS::Unbound::Async -e'my $dns = Cpanel::DNS::Unbound::Async->new(); my $cv = AE::cv(); my $mx_hr = Cpanel::SMTP::GetMX::assemble_mx_table($dns); for my $d (keys %$mx_hr) { $mx_hr->{$d}->then(sub { print Dumper($d, shift()) }, sub { warn shift }) } Promise::ES6->all( [values %$mx_hr] )->finally($cv); $cv->recv()'

sub assemble_mx_table ( $dns, $domains_ar ) {
    my %domain_mx;

    for my $domain (@$domains_ar) {
        $domain_mx{$domain} = $dns->ask( $domain, 'MX' )->then(
            sub ($result) {
                my @promises;

                my @promise_result;

                for my $mx_ar ( @{ $result->decoded_data() } ) {
                    my ( $preference, $name ) = @$mx_ar;

                    my $name_result_hr = {
                        preference => $preference,
                        exchange   => $name,
                    };

                    push @promise_result, $name_result_hr;

                    # Empty MX “exchange”s do exist.
                    # As of this writing, for example:
                    #
                    # > unbound-host -t MX canada.com
                    # canada.com mail is handled by 0 .
                    #
                    if ( length $name ) {

                        for my $addrtype (qw( A AAAA )) {
                            my $ret_key = _RET_HASH_XFORM()->{$addrtype};

                            push @promises, $dns->ask( $name, $addrtype )->then(
                                sub ($result) {
                                    push @{ $name_result_hr->{$ret_key} }, @{ $result->decoded_data() };
                                },

                                sub ($err) {
                                    return _warn_passed( $name, $addrtype, $err );
                                },
                            );
                        }
                    }
                }

                return Promise::ES6->all( \@promises )->then(
                    sub {
                        return \@promise_result;
                    }
                );
            },

            sub ($err) {
                return _warn_passed( $domain, 'MX', $err );
            },
        );
    }

    return \%domain_mx;
}

sub _warn_passed ( $qname, $qtype, $err ) {
    local $@;

    if ( eval { $err->isa('Cpanel::Exception') } ) {
        warn $err->to_string_no_id() . "\n";
    }
    else {
        local $@ = "DNS query $qname/$qtype: $err";
        warn;
    }

    return undef;
}

1;
