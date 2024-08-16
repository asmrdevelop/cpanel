
package Cpanel::SSL::Hostname::Domains;

# cpanel - Cpanel/SSL/Hostname/Domains.pm          Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::SSL::Hostname::Domains

=head1 SYNOPSIS

    my @cert_domains = Cpanel::SSL::Hostname::Domains::get_desired_cert_domains();

=head1 FUNCTIONS

=cut

use Cpanel::ArrayFunc::Uniq           ();
use Cpanel::Hostname                  ();
use Cpanel::WebVhosts::AutoDomains    ();
use Whostmgr::Hostname::History::Read ();

sub _get_hostnames() {
    my $old_hostnames_ar = Whostmgr::Hostname::History::Read::get();

    # The initial rollout of the hostnames-history datastore
    # allowed for a re-save of the current hostname to create a
    # superfluous entry in the datastore. We guard against that now,
    # but there will still be hosts out there with the problem.
    #
    # We could migrate them away, but it’s easier just to tolerate the
    # problem here.
    #
    return Cpanel::ArrayFunc::Uniq::uniq(
        Cpanel::Hostname::gethostname(),
        ( map { $_->{'old_hostname'} } @$old_hostnames_ar ),
    );
}

=head2 my @domains = get_desired_cert_domains()

Returns the list of domains and subdomains that should be included on a
server's hostname SSL certificate. This includes the current hostname and its
related service subdomains as well as the server's previous hostnames contained
in the hostname history.

See the usage of L<Whostmgr::Hostname::History::Write> for the specifics of
what historical hostnames are included and the constants of this module for the
subdomains that are included.

=cut

sub get_desired_cert_domains() {
    return map {
        my $hn = $_;
        (
            $hn,
            ( map { "$_.$hn" } Cpanel::WebVhosts::AutoDomains::ALL_POSSIBLE_HOSTNAME_SUBDOMAINS() ),
        )
    } _get_hostnames();
}

1;
