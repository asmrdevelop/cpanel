# cpanel - Whostmgr/DNS/Cluster/UI/Restartclustermember.pm
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Whostmgr::DNS::Cluster::UI::Restartclustermember;

use strict;
use warnings;

use Whostmgr::DNS::Cluster::UI ();
use Cpanel::DNSLib::PeerStatus ();

sub render {
    my $callback = sub {
        my ( $clustermaster, $user ) = @_;
        my $status     = Cpanel::DNSLib::PeerStatus::restart_cluster_member( $clustermaster, $user );
        my $successmsg = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'Server “[_1]” restarted [asis,named] successfully.', $clustermaster );
        my $failmsg    = Whostmgr::DNS::Cluster::UI::lh()->maketext( 'Server “[_1]” failed to restart [asis,named].',      $clustermaster );
        return ( $status, $status ? $successmsg : $failmsg );
    };
    return Whostmgr::DNS::Cluster::UI::render_common($callback);
}

1;

__END__

=head1 NAME

Whostmgr::DNS::Cluster::UI::Restartclustermember

=head1 DESCRIPTION

Page that restarts the cluster member's DNS service

=head1 SYNOPSIS

    require Whostmgr::DNS::Cluster::UI::Restartclustermember;
    Whostmgr::DNS::Cluster::UI::Restartclustermember::render();

=head1 SUBROUTINES

=head2 render()

Print everything needed to render the page aside from headers.

This function does not return anything.
