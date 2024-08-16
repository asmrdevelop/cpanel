package Cpanel::SSL::DCV::DNS::Result;

# cpanel - Cpanel/SSL/DCV/DNS/Result.pm            Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::Result

=head1 DESCRIPTION

This module encapsulates a DNS DCV result. It provides logic for
negotiating domain-to-zone lookups.

=cut

#----------------------------------------------------------------------

use Cpanel::DnsUtils::Name ();
use Cpanel::LocaleString   ();

#----------------------------------------------------------------------

=head1 METHODS

=head2 I<CLASS>->new( $VALUE, \@ZONES, \%ZONE_RESULT )

Instantiates this class.

$VALUE is the value that was set in the DNS DCV test records.

@ZONES is the full list of zones that were attempted to be modified.

%ZONE_RESULT is the result of
C<Cpanel::SSL::DCV::DNS::check_multiple_nonfatal()> but with the zone
names (not the queried record name) as the hash keys.

=cut

sub new {
    my ( $class, $value, $zones_ar, $zone_result_hr ) = @_;

    my %selfhash = (
        value       => $value,
        all_zones   => $zones_ar,
        zone_result => $zone_result_hr,
    );

    return bless \%selfhash, $class;
}

=head2 I<OBJ>->get_for_domain( $DOMAIN )

Returns a hash reference that indicates the DNS DCV result for $DOMAIN.

That hash reference’s members are:

=over

=item * C<zone> - The actual zone that was modified. (e.g., if I do
DNS DCV on C<www.example.com>, the zone will be C<example.com>.)

=item * C<dcv_string> - The value that was expected in the DNS query result.
(NB: This is identical to the $VALUE given to the constructor.)

=item * C<query_results> - See C<Cpanel::SSL::DCV::DNS::check_multiple_nonfatal()>.

=item * C<succeeded> - See C<Cpanel::SSL::DCV::DNS::check_multiple_nonfatal()>.

=item * C<failure_reason> - See C<Cpanel::SSL::DCV::DNS::check_multiple_nonfatal()>.

=back

Note that any $DOMAIN that doesn’t match one of the @ZONES given to the
constructor is assumed to be a failure to update DNS to prepare for DCV.

=cut

sub get_for_domain ( $self, $domain ) {
    my $zone = Cpanel::DnsUtils::Name::get_longest_short_match(
        $domain,
        $self->{'all_zones'},
    );

    if ( !$zone ) {
        my @zones = @{ $self->{'all_zones'} };
        die( ref($self) . ": “$domain” doesn’t match any of this object’s zones! (@zones)" );
    }

    my %result;

    if ( my $zone_result_hr = $self->{'zone_result'}{$zone} ) {
        %result = %$zone_result_hr;
    }
    else {
        %result = (
            succeeded      => 0,
            query_results  => undef,
            failure_reason => Cpanel::LocaleString->new( 'The system failed to modify the zone “[_1]” to prepare for [asis,DNS] [asis,DCV].', $zone ),
        );
    }

    @result{ 'zone', 'dcv_string' } = ( $zone, $self->{'value'} );

    return \%result;
}

1;
