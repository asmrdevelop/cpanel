package Cpanel::DNS::Unbound::Result;

# cpanel - Cpanel/DNS/Unbound/Result.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

#----------------------------------------------------------------------

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Result

=head1 DESCRIPTION

This adds methods to the response from a L<DNS::Unbound> query that are of
use to cPanel & WHM.

Once cPanel & WHM upgrades to a recent DNS::Unbound release this class
should subclass L<DNS::Unbound::Result>.

=cut

#----------------------------------------------------------------------

use Cpanel::DNS::Rdata ();

use parent qw( DNS::Unbound::Result );

#----------------------------------------------------------------------

=head1 STATIC FUNCTIONS

=head2 convert( $DNS_UNBOUND_RESULT, $DEBUG_TEXT )

This converts a given L<DNS::Unbound::Result> instance into an
instance of this class. It also stores $DEBUG_TEXT such that
the object can access this value.

Nothing is returned. (This is to ensure that the caller understands
that $DNS_UNBOUND_RESULT is modified B<in-place>.)

=cut

sub convert ($dns_unbound_result) {
    bless $dns_unbound_result, __PACKAGE__;

    return;
}

#----------------------------------------------------------------------

=head1 METHODS

The following are available in addition to the methods inherited
from L<DNS::Unbound::Result>:

=head2 $decoded_ar = I<OBJ>->decoded_data()

Returns an array reference of I<OBJ>’s data, decoded as per the following:

=over

=item * C<A> and C<AAAA> records are given as ASCII.

=item * C<NS>, C<CNAME>, and C<PTR> records are given as domain names,
B<without> a trailing C<.>.

=item * C<MX> records are given as array references: [priority, name],
with the name’s trailing C<.> trimmed.

=item * C<TXT> records are given as a single string that plainly concatenates
the component character-strings together. This prevents applications from
distinguishing, e.g., (C<hello there>) from (C<hello>, C< there>), but it’s
the way cPanel & WHM has worked for some time.

=item * C<SOA> records are given as array references of the list of values
that RFC 1035 describes, with the names’ trailing C<.> trimmed.

=back

If I<OBJ> doesn’t represent a DNS query response of one of the above
types, an exception is thrown.

=cut

sub decoded_data ($self) {
    my $qtypenum = $self->{'qtype'};

    my $xform_cr = Cpanel::DNS::Rdata->can("parse_$qtypenum") or do {

        # This shouldn’t happen in production.
        die "$self: can’t decode RR data of type $qtypenum!";
    };

    my @copy = @{ $self->{'data'} };
    $xform_cr->( \@copy );

    return \@copy;
}

1;
