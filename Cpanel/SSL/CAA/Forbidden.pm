# cpanel - Cpanel/SSL/CAA/Forbidden.pm             Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
package Cpanel::SSL::CAA::Forbidden;

use cPstrict;

use Cpanel::DNS::Unbound::Async ();
use Cpanel::DnsRoots::CAA       ();
use Cpanel::PromiseUtils        ();

=encoding utf-8

=head1 NAME

Cpanel::SSL::CAA::Forbidden

=head1 SYNOPSIS

    my @filtered = Cpanel::SSL::CAA::Forbidden::filter_caa_forbidden();

=head1 FUNCTIONS

=head2 my @filtered = filter_caa_forbidden( $domains, $caa_strings, $callback )

Takes a list of domains and CAA strings and filters out any of the domains
where the domain’s DNS CAA records do not match the provided CAA strings.

=over

=item C<$domains> - An C<ARRAYREF> of domains to check.

=item C<$caa_strings> - An C<ARRAYREF> of permitted CAA strings.

=item C<$callback> - An (options) C<CODEREF> that will be called if the domain
forbids issuance by the CAA strings. The callback will receive two arguments:

=over

=item C<$domain> - The domain for which issuance was forbidden by the CAA DNS records.

=item C<$rrset> - The DNS name of the record that indicates the forbiddance.
Either the domain itself or one of its parents.

=back

=back

=cut

sub filter_caa_forbidden ( $domains, $caa_strings, $callback ) {
    my $unbound     = Cpanel::DNS::Unbound::Async->new();
    my $promises_ar = Cpanel::DnsRoots::CAA::get_forbiddance_promises(
        $unbound,
        $caa_strings,
        $domains,
    );

    my @forbiddances = map { $_->get() } Cpanel::PromiseUtils::wait_anyevent(@$promises_ar);

    my %forbid;
    @forbid{@$domains} = @forbiddances;

    return grep {
        my $blocked = $forbid{$_};
        $callback->( $_, $blocked->[0] ) if $blocked && $callback;
        !$blocked;
    } @$domains;
}

1;
