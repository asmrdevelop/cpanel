package Cpanel::SSL::DCV::DNS::User;

# cpanel - Cpanel/SSL/DCV/DNS/User.pm              Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::SSL::DCV::DNS::User - DNS-based DCV logic to run as a user

=head1 SYNOPSIS

    my $results_ar = Cpanel::SSL::DCV::DNS::User::verify_domains(
        username => $username,
    );

=cut

#----------------------------------------------------------------------

use Cpanel::PwCache       ();
use Cpanel::SSL::DCV::DNS ();

#----------------------------------------------------------------------

=head1 ANCESTOR DOMAIN OPTIMIZATION

Because control of a domain implies control over all subdomains of that
domain, we can optimize by minimizing the amount of “DNS churn” thus:

=over

=item 1. The given C<domains> are reduced to the “ancestral set”; e.g.,
if C<foo.bar.baz.com> and C<baz.com> are both given, only C<baz.com> will
be DCVed. This applies even if there is a separate DNS zone for
C<foo.bar.baz.com> or C<bar.baz.com>.

=item 2. The same reduction is applied to zone names. So if, for some reason,
the account has separate zones for C<foo.bar.com> and C<bar.com>, only the
latter will be used for DCV.

=item 3. A given zone is only tested once. So if C<a.foo.com> and C<b.foo.com>
both live on the C<foo.com> zone, there is only one “real” DCV action.

=back

NB: This is the same reasoning behind Let’s Encrypt’s issuance of
wildcard certificates; however, for some reason they
don’t honor DCV against the parent domain for non-wildcards (as of
April 2018, anyway).

There is no provision made to remove the DNS record because it
shouldn’t be necessary.

=head1 IMPLEMENTATION NOTES

The logic here is that we identify the most ancestral zones
for the given set of domains then verify that a change to that zone’s
base domain is publicly visible. The base domain and all of its subdomains
thus either validated or failed.

That may cover all cases, though: it assumes that if the box can validate
a subdomain, then it can validate all known ancestor domains of that
subdomain. This would fail in setups where the base domain points somewhere
else but the subdomain is here--and it lives on a locally-hosted zone.
In this case it would be possible for us to DCV the subdomain but not the
base domain, which breaks the above-mentioned assumption.

For now we won’t accommodate that scenario.

=head1 FUNCTIONS

=head2 verify_domains( %OPTS )

To be run B<unprivileged>. %OPTS is:

=over

=item C<domains> - An arrayref of FQDNs.

=back

The return is an arrayref of hashrefs. Each
given C<domains> corresponds to a hashref in the response. Order is
preserved. Each hashref looks thus:

=over

=item * C<zone> - The zone that was altered and queried.

=item * C<dcv_string> - The string that was expected as a result in the query.

=item * … and the values from the return of
C<Cpanel::SSL::DCV::DNS::check_multiple_nonfatal()>.

=back

=cut

sub verify_domains {
    my (@opts_kv) = @_;

    return Cpanel::SSL::DCV::DNS::_verify_domains(
        \&_install_as_user,
        @opts_kv,
        username => Cpanel::PwCache::getusername(),
    );
}

sub _install_as_user {
    my ($zones_ar) = @_;

    require Cpanel::AdminBin::Call;

    return Cpanel::AdminBin::Call::call(
        'Cpanel', 'zone', 'SET_UP_FOR_DNS_DCV',
        $zones_ar,
    );
}

1;
