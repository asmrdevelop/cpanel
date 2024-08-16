package Cpanel::DnsRoots::ErrorWarning;

# cpanel - Cpanel/DnsRoots/ErrorWarning.pm         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DnsRoots::ErrorWarning - normalized error handling for asynchronous
DNS queries

=head1 SYNOPSIS

    my $catcher_cr = Cpanel::DnsRoots::ErrorWarning::create_dns_query_promise_catcher( 'example.com', 'NS' );

    my $resolver = Cpanel::DNS::Unbound::Async->new();

    my $always_fulfills = $resolver->ask('example.com', 'NS')->then(
        sub { ... },
        $catcher_cr,
    );

=head1 DESCRIPTION

This module normalizes error-catching logic for different types of
promise-based recursive DNS queries.

=cut

#----------------------------------------------------------------------

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 $cr = create_dns_query_promise_catcher( $QNAME, $QTYPE )

Returns a coderef that converts its passed argument to a Perl warning
and returns undef. $QNAME and $QTYPE are the DNS query’s parameters.

=cut

sub create_dns_query_promise_catcher ( $qname, $qtype ) {
    return sub ($err) {
        local $@;

        if ( eval { $err->isa('Cpanel::Exception::DNS::ErrorResponse') } ) {
            my $result_obj = $err->get('result');

            my $rcode = $result_obj->rcode();

            $err = $err->get_rcode_string() . " ($rcode)";
        }
        else {
            $err = Cpanel::Exception::get_string($err);
        }

        warn("DNS query error ($qname/$qtype): $err\n");

        return undef;
    }
}

1;
