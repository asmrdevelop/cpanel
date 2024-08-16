# cpanel - Whostmgr/DNS/Cluster/UI/Upgradeclustermember.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::DNS::Cluster::UI::Upgradeclustermember;

use strict;
use warnings;

use Whostmgr::DNS::Cluster::UI ();
use Cpanel::DNSLib::PeerStatus ();

sub render {
    my $callback = sub {
        my ( $clustermaster, $user ) = @_;
        my $status     = Cpanel::DNSLib::PeerStatus::upgrade_cluster_member( $clustermaster, $user );
        my $successmsg = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'The server “[_1]” configured [asis,PowerDNS] as its nameserver.',          $clustermaster );
        my $failmsg    = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'The server “[_1]” failed to configure [asis,PowerDNS] as its nameserver.', $clustermaster );
        return ( $status, $status ? $successmsg : $failmsg );
    };
    return Whostmgr::DNS::Cluster::UI::render_common($callback);
}

1;

__END__

=head1 NAME

Whostmgr::DNS::Cluster::UI::Upgradeclustermember

=head1 DESCRIPTION

Page that upgrades cluster members to pdns

=head1 SYNOPSIS

    require Whostmgr::DNS::Cluster::UI::Upgradeclustermember;
    Whostmgr::DNS::Cluster::UI::Upgradeclustermember::render();

=head1 SUBROUTINES

=head2 render()

Print everything needed to render the page aside from headers.

This function does not return anything.
