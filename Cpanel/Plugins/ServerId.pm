# cpanel - plugins/cpanel/koality/perl/usr/local/cpanel/Cpanel/Plugins/ServerId.pm             Copyright 2023 cPanel, L.L.C.
#                                                           All rights Reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited

package Cpanel::Plugins::ServerId;

use strict;
use warnings;

use v5.20;
use experimental qw(signatures);

=head1 MODULE

C<Cpanel::Plugins::ServerId>

=head1 DESCRIPTION

C<Cpanel::Plugins::ServerId> provides helper functions for retrieving the unique server id for a server.

=head1 SYNOPSIS

  use Cpanel::Plugins::ServerId();
  say "ServerID: " . Cpanel::Plugins::ServerId::get_server_id();

=head1 FUNCTIONS

=cut

sub get_server_id() {
    require Cpanel::DIp::MainIP;
    require Cpanel::AdminBin::Call;

    my $uuid = Cpanel::AdminBin::Call::call( "Cpanel", "site_quality_monitoring", "GET_SERVER_UUID", {} );
    chomp( my $ip = Cpanel::DIp::MainIP::getpublicmainserverip() );

    return "$uuid-$ip";
}

1;
