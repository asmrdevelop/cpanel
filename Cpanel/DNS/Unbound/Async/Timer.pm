package Cpanel::DNS::Unbound::Async::Timer;

# cpanel - Cpanel/DNS/Unbound/Async/Timer.pm       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::DNS::Unbound::Async::Timer

=head1 DESCRIPTION

This class implements L<Cpanel::Async::InactivityTimer> for
L<Cpanel::DNS::Unbound::Async>.

=cut

#----------------------------------------------------------------------

use parent qw(Cpanel::Async::InactivityTimer);

use AnyEvent ();

use Cpanel::Exception ();

#----------------------------------------------------------------------

=head2 _TIME_QUERY_OUT ( $class, $query_item_ar )

$cpanel_dns_unbound_async_query is a C<Cpanel::DNS::Unbound::Async::Query>
object

=cut

sub _TIME_QUERY_OUT ( $class, $cpanel_dns_unbound_async_query ) {    ## no critic qw(Subroutines::ProhibitManyArgs) -- seems like a perl critic bug
    my $qname               = $cpanel_dns_unbound_async_query->qname();
    my $qtype               = $cpanel_dns_unbound_async_query->qtype();
    my $dns_unbound_promise = $cpanel_dns_unbound_async_query->dns_unbound_promise();

    $dns_unbound_promise->cancel();

    $cpanel_dns_unbound_async_query->rejector()->( Cpanel::Exception::create_raw( 'Timeout', "DNS request timeout: $qname/$qtype" ) );

    return;
}

=head2 _GET_NEXT_QUERY_INDEX_AND_ITS_TIMEOUT ( $class, $query_data_hr )

$query_data_hr is a hashref of queries with the values being
C<Cpanel::DNS::Unbound::Async::Query> objects

=cut

sub _GET_NEXT_QUERY_INDEX_AND_ITS_TIMEOUT ( $class, $query_data_hr ) {
    my @query_keys_sorted = sort { $query_data_hr->{$a}->minimum_timeout_time() <=> $query_data_hr->{$b}->minimum_timeout_time() } keys %$query_data_hr;

    return ( $query_keys_sorted[0], $query_data_hr->{ $query_keys_sorted[0] }->minimum_timeout_time() - AnyEvent->time() );
}

1;
