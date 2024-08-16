package Cpanel::Exception::DNS::ErrorResponse;

# cpanel - Cpanel/Exception/DNS/ErrorResponse.pm   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::Exception::DNS::ErrorResponse

=head1 DISCUSSION

An exception class that represents a DNS query response whose response code
(RCODE) is nonzero.

=head1 ARGUMENTS

This class expects one argument: C<result>, which is a L<DNS::Unbound::Result>
instance. This will be the resolution of the promise that L<DNS::Unbound>’s
C<resolve_async()> returns.

=cut

#----------------------------------------------------------------------

use parent qw( Cpanel::Exception );

use Net::DNS::Parameters ();

use Cpanel::LocaleString ();

#----------------------------------------------------------------------

sub _default_phrase ( $self, $mt_args_ar ) {
    my $ub_result = $self->get('result');

    my $qtype_str = Net::DNS::Parameters::typebyval( $ub_result->qtype() );
    my $rcode_str = $self->get_rcode_string();

    return Cpanel::LocaleString->new( 'DNS returned “[_1]” (code [numf,_2]) in response to the system’s query for “[_3]”’s “[_4]” records.', $rcode_str, $ub_result->rcode(), $ub_result->qname(), $qtype_str );
}

sub get_rcode_string ($self) {
    return Net::DNS::Parameters::rcodebyval( $self->get('result')->rcode() );
}

1;
