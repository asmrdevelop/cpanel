package Cpanel::LinkedNode::HostnameUpdate;

# cpanel - Cpanel/LinkedNode/HostnameUpdate.pm     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

use cPstrict;

=encoding utf-8

=head1 NAME

Cpanel::LinkedNode::HostnameUpdate

=head1 SYNOPSIS

    Cpanel::LinkedNode::HostnameUpdate::propagate($alias, $old_hostname);

=head1 DESCRIPTION

This propagates hostname changes to any resources that may duplicate
that hostname. For example, this updates C<CNAME> records for C<mail.>
subdomains (i.e., for C<Mail> linkages).

=cut

#----------------------------------------------------------------------

use Cpanel::LinkedNode::List ();
use Cpanel::DnsUtils::Batch  ();
use Cpanel::DnsUtils::Fetch  ();
use Cpanel::UserZones::User  ();
use Cpanel::ZoneFile         ();

use Cpanel::LinkedNode::Index::Read ();

#----------------------------------------------------------------------

=head1 FUNCTIONS

=head2 propagate($ALIAS, $OLD_HOSTNAME)

Finds all users who use the linked node with alias $ALIAS and
propagates that linked node’s current hostname appropriately.

This returns nothing.

=cut

sub propagate ( $alias, $old_hostname ) {

    # NB: We could read the zone file to grab the $old_hostname—especially
    # since we’re about to read it anyway!—but it’s safer to use the same
    # data point as Cpanel::LinkedNode.

    my $index_hr = Cpanel::LinkedNode::Index::Read::get();

    my $hostname = $index_hr->{$alias}->hostname();

    my $noderelations_ar = Cpanel::LinkedNode::List::list_user_worker_nodes();

    my @to_set;

    for my $relation_hr (@$noderelations_ar) {
        next if $relation_hr->{'alias'} ne $alias;

        # For now we only handle Mail.
        next if $relation_hr->{'type'} ne 'Mail';

        my $username = $relation_hr->{'user'};

        my @zonenames = Cpanel::UserZones::User::list_user_dns_zone_names($username);

        my $zone_ref = Cpanel::DnsUtils::Fetch::fetch_zones(
            zones => \@zonenames,
        );

        for my $zonename (@zonenames) {
            push @to_set, [ "mail.$zonename", 'CNAME', $hostname ];

            my $zone_txt = $zone_ref->{$zonename};
            my $zone_obj = Cpanel::ZoneFile->new(
                domain => $zonename,
                text   => $zone_txt,
            );

            my $mxs_ar = $zone_obj->find_records( type => 'MX' );

            for my $mxrec (@$mxs_ar) {
                next if $mxrec->{'exchange'} ne $old_hostname;

                my $recname = $mxrec->{'name'} =~ s<\.\z><>r;

                push @to_set, [ $recname, 'MX', "$mxrec->{'preference'} $hostname" ];
            }
        }
    }

    Cpanel::DnsUtils::Batch::set( \@to_set );

    return;
}

1;
