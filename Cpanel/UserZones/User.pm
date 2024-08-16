package Cpanel::UserZones::User;

# cpanel - Cpanel/UserZones/User.pm                Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Cpanel::UserZones::User - unprivileged user DNS zone logic

=head1 SYNOPSIS

    my @zones = list_user_dns_zone_names($username)

=head1 DESCRIPTION

The “sure-fire” way to retrieve all of a user’s zones is to contact
dnsadmin; however, for certain applications it’s “good enough” to
deduce the list via the user’s local configuration data.

Ideally this would be adequate in all cases, but historically there
were bugs where cPanel-created subdomains received DNS zones of their own.

Cases where this module’s method is adequate for production include:

=over

=item 1. You’re working only with accounts that are new enough not to have
been affected by old, buggy behavior that created DNS zones for cPanel-created
subdomains.

=item 2. You’re creating a new DNS record, which can exist just fine on
a parent zone without affecting DNS query results. (This is the case with,
e.g., DNS-based DCV as implemented in v74.)

=back

=head1 SEE ALSO

L<Cpanel::DomainLookup> implements similar logic but reads the
a vhost config cache. It should give the same results.

=cut

use Cpanel::Config::LoadCpUserFile ();
use Cpanel::Config::WebVhosts      ();
use Cpanel::Context                ();
use Cpanel::Set                    ();

=head1 FUNCTIONS

=head2 @zones = list_user_dns_zone_names( USERNAME )

Returns a list of zone names for the user. This list is deduced by comparing
the cpuser data’s domain list with web vhost data (i.e., userdata) and removing
web vhost subdomains from the cpuser list. The result should consist of the
account’s main domain, parked domains, and any independent zones that the
account controls.

=cut

sub list_user_dns_zone_names {
    my ($username) = @_;

    die "Need username!" if !$username;

    Cpanel::Context::must_be_list();

    my $cpuser_ref = Cpanel::Config::LoadCpUserFile::load($username);

    my @created_domains = (
        $cpuser_ref->{'DOMAIN'},
        ref $cpuser_ref->{'DOMAINS'} ? @{ $cpuser_ref->{'DOMAINS'} } : (),
    );

    my $web_vh = Cpanel::Config::WebVhosts->load($username);

    return Cpanel::Set::difference(
        \@created_domains,
        [ $web_vh->subdomains() ],
    );
}

1;
