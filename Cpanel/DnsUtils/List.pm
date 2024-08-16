package Cpanel::DnsUtils::List;

# cpanel - Cpanel/DnsUtils/List.pm                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use strict;
use warnings;

use Cpanel::Config::LoadUserDomains ();
use Cpanel::Config::LoadUserOwners  ();
use Cpanel::DnsUtils::AskDnsAdmin   ();

sub listzones {
    my %OPTS = @_;
    my @DOMAINS;
    my $userdomains_ref = Cpanel::Config::LoadUserDomains::loaduserdomains( undef, 1 );

    require Cpanel::LinkedNode::List;

    if ( defined $OPTS{'source'} && $OPTS{'source'} eq 'userdomains' ) {
        delete $userdomains_ref->{'*'};
        @DOMAINS = map { $_ } keys %{$userdomains_ref};
    }
    else {
        @DOMAINS = split( "\n", Cpanel::DnsUtils::AskDnsAdmin::askdnsadmin('GETZONELIST') );
    }

    my $owner_hr = Cpanel::Config::LoadUserOwners::loadtrueuserowners( undef, 1, 1 );

    my $user_workloads_ar = Cpanel::LinkedNode::List::list_user_workloads();

    my %is_child_lookup;
    @is_child_lookup{ map { $_->{'user'} } @$user_workloads_ar } = ();

    my @dnslist;
    foreach my $domain ( sort @DOMAINS ) {
        my $domainuser = $userdomains_ref->{$domain} || '';
        my $owner      = $owner_hr->{$domainuser}    || 'root';

        # Do not include domains where $domainuser is a child account
        next if exists $is_child_lookup{$domainuser};

        if ( !$OPTS{'hasroot'} && $owner ne $ENV{'REMOTE_USER'} ) {

            # Used by the 'set_zone_ttl' CLI to filter zones
            # belonging to a particular user.
            if ( defined $OPTS{'user'} && $OPTS{'user'} eq $domainuser ) {
                push @dnslist, $domain;
            }
            next;
        }
        push @dnslist, $domain;
    }
    return \@dnslist;
}
1;
