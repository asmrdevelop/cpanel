# cpanel - Whostmgr/DNS/Cluster/UI/Monitorclustermember.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::DNS::Cluster::UI::Monitorclustermember;

use strict;
use warnings;

use Whostmgr::DNS::Cluster::UI ();
use Cpanel::DNSLib::PeerStatus ();

sub render {
    my $callback = sub {
        my ( $clustermaster, $user ) = @_;
        my $status     = Cpanel::DNSLib::PeerStatus::monitor_cluster_member( $clustermaster, $user );
        my $successmsg = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'The server “[_1]” configured the nameserver as a monitored service.',          $clustermaster );
        my $failmsg    = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'The server “[_1]” failed to configure the nameserver as a monitored service.', $clustermaster );
        return ( $status, $status ? $successmsg : $failmsg );
    };
    return Whostmgr::DNS::Cluster::UI::render_common($callback);
}

1;

__END__

=head1 NAME

Whostmgr::DNS::Cluster::UI::Monitorclustermember

=head1 DESCRIPTION

Page that configures cluster members to monitor their DNS service

=head1 SYNOPSIS

    require Whostmgr::DNS::Cluster::UI::Monitorclustermember;
    Whostmgr::DNS::Cluster::UI::Monitorclustermember::render();

=head1 SUBROUTINES

=head2 render()

Print everything needed to render the page aside from headers.

This function does not return anything.
